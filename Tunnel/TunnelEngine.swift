import Foundation

/// NE 进程内的 EasyTier 编排：起实例、找房主、加转发、汇报状态。
///
/// 设计要点：
/// - 两端都用 `no_tun`，iOS 不创建 TUN，不需要用户态协议栈；
/// - 房客拿端口靠「解析房主 hostname」，不实现陶瓦的 scaffolding TCP 协议；
/// - 加转发优先走 PatchConfig RPC，失败自动降级为「带 port_forward 重启实例」。
final class TunnelEngine {

    let session: SessionConfig
    let logger: TunnelLogger

    private(set) var phase: ProviderStatus.Phase = .idle
    private(set) var detail = ""
    private(set) var connectAddress: String?
    private(set) var hostPort: Int?
    private(set) var natType: String?
    private(set) var peerCount = 0
    private(set) var errorText: String?

    private var pollTimer: DispatchSourceTimer?
    private let workQueue = DispatchQueue(label: "terracotta.engine")
    private var didApplyForward = false
    private var startedAt = Date()

    init(session: SessionConfig, logger: TunnelLogger) {
        self.session = session
        self.logger = logger
    }

    // MARK: - 生命周期

    func start() {
        startedAt = Date()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let docs {
            EasyTierIOS.configureDiagnosticLogging(directory: docs.appendingPathComponent("easytier-logs").path, enabled: true)
        }

        guard let code = InviteCode.parse(session.inviteCode) else {
            fail("邀请码解析失败")
            return
        }

        do {
            if session.role == .host {
                phase = .starting
                detail = "正在启动房主模式"
                let toml = EasyTierConfigBuilder.hostTOML(
                    code: code,
                    mcPort: session.minecraftPort,
                    nodes: session.publicNodes,
                    instanceName: session.instanceName
                )
                try EasyTierIOS.runInstance(toml: toml)
                logger.log("房主实例已启动，hostname=\(SessionConfig.hostHostnamePrefix)\(session.minecraftPort)")
                phase = .ready
                detail = "房间已开，等朋友加入"
                startPolling()
            } else {
                phase = .starting
                detail = "正在启动组网核心"
                let toml = EasyTierConfigBuilder.guestTOML(
                    code: code,
                    nodes: session.publicNodes,
                    instanceName: session.instanceName
                )
                try EasyTierIOS.runInstance(toml: toml)
                logger.log("房客实例已启动，网络 \(code.networkName)")
                phase = .negotiating
                detail = "P2P 打洞中，正在等公共节点回连"
                startPolling()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        EasyTierIOS.stopAll()
        EasyTierIOS.flushDiagnosticLogging()
        phase = .stopped
        detail = "已断开"
        logger.log("实例已全部停止")
    }

    func snapshot() -> ProviderStatus {
        ProviderStatus(
            phase: phase,
            detail: detail,
            connectAddress: connectAddress,
            hostPort: hostPort,
            natType: natType,
            peerCount: peerCount,
            logs: logger.snapshot,
            errorText: errorText,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    // MARK: - 轮询

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(3), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        pollTimer = timer
    }

    private func tick() {
        refreshPeers()

        if session.role == .host {
            if phase != .ready {
                phase = .ready
                detail = "房间已开，等朋友加入"
            }
            return
        }

        guard !didApplyForward else { return }

        guard let discoveredPort = discoverHostPort() else {
            if Date().timeIntervalSince(startedAt) > 45 {
                phase = .discoveringPeer
                detail = "已接入网络，但还没发现房主。检查房间码是否一致、房主是否在线。"
            }
            return
        }

        hostPort = discoveredPort
        phase = .forwarding
        detail = "发现房主端口 \(discoveredPort)，正在建立通道"
        logger.log("发现房主端口 \(discoveredPort)")

        applyForward(hostPort: discoveredPort)
    }

    private func refreshPeers() {
        let infos = EasyTierIOS.collectNetworkInfos()
        peerCount = countPeers(in: infos)
        if let nat = firstString(matching: ["nat_type", "natType"], in: infos) {
            natType = nat
        }
    }

    private func countPeers(in object: Any) -> Int {
        var count = 0
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if key.lowercased().contains("peer"), let array = child as? [Any] {
                        count = max(count, array.count)
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        return count
    }

    private func firstString(matching keys: [String], in object: Any) -> String? {
        func walk(_ value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                for key in keys {
                    if let hit = dictionary[key] as? String { return hit }
                }
                for (_, child) in dictionary {
                    if let hit = walk(child) { return hit }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let hit = walk(child) { return hit }
                }
            }
            return nil
        }
        return walk(object)
    }

    /// 在 peer 信息里找 hostname 形如 `scaffolding-mc-server-<端口的节点>`，取出房主端口。
    /// 用深度字符串扫描，避免依赖 EasyTier 运行信息的具体 JSON 结构。
    private func discoverHostPort() -> Int? {
        let needle = SessionConfig.hostHostnamePrefix

        var candidates: [String] = []
        func walk(_ value: Any) {
            if let string = value as? String, string.contains(needle) {
                candidates.append(string)
                return
            }
            if let dictionary = value as? [String: Any] {
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(EasyTierIOS.collectNetworkInfos())

        // 兜底：走管理 RPC 列 peer
        if candidates.isEmpty,
           let rpc = try? EasyTierIOS.callJSONRPC(
               service: "api.config.ConfigRpcService",
               method: "ListPeer",
               payload: "{\"instance\":{\"name\":\"\(session.instanceName)\"}}"
           ) {
            walk(rpc)
        }

        for candidate in candidates {
            guard let range = candidate.range(of: needle) else { continue }
            let tail = candidate[range.upperBound...]
            // hostname 可能带后缀，取开头的连续数字
            let digits = tail.prefix { $0.isNumber }
            if let port = Int(digits), (1...65535).contains(port) {
                return port
            }
        }
        return nil
    }

    // MARK: - 端口转发

    private func applyForward(hostPort: Int) {
        let listen = hostPort

        // 主路径：动态 PatchConfig
        do {
            let payload = EasyTierConfigBuilder.patchConfigPayload(
                instanceName: session.instanceName,
                listen: listen,
                hostPort: hostPort
            )
            _ = try EasyTierIOS.callJSONRPC(
                service: "api.config.ConfigRpcService",
                method: "PatchConfig",
                payload: payload
            )
            logger.log("已通过 PatchConfig 添加转发 0.0.0.0:\(listen) → 10.144.144.1:\(hostPort)")
            finishForward(listen: listen)
            return
        } catch {
            logger.log("PatchConfig 未生效（\(error.localizedDescription)），改用重启实例带 port_forward")
        }

        // 降级路径：停掉再带 [[port_forward]] 重启
        do {
            EasyTierIOS.stopAll()
            guard let code = InviteCode.parse(session.inviteCode) else {
                fail("邀请码解析失败")
                return
            }
            let toml = EasyTierConfigBuilder.guestTOML(
                code: code,
                nodes: session.publicNodes,
                instanceName: session.instanceName,
                forward: (listen: listen, hostPort: hostPort)
            )
            try EasyTierIOS.runInstance(toml: toml)
            logger.log("已以 port_forward 方式重启实例，监听 0.0.0.0:\(listen)")
            finishForward(listen: listen)
        } catch {
            fail("添加端口转发失败：\(error.localizedDescription)")
        }
    }

    private func finishForward(listen: Int) {
        didApplyForward = true
        connectAddress = "127.0.0.1:\(listen)"
        phase = .ready
        detail = "通道就绪，在游戏里连接 \(connectAddress!)"
        logger.log("就绪：\(connectAddress!)")
    }

    private func fail(_ message: String) {
        phase = .failed
        detail = message
        errorText = message
        logger.log("失败：\(message)")
    }
}
