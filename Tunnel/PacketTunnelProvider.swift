import Foundation
import NetworkExtension

/// Network Extension 主类。
///
/// 它有两个职责：
/// 1. **保活容器**：隧道一 connected，系统就持续为本进程保留运行时间，主 App 挂起/被杀都不影响组网；
/// 2. **EasyTier 宿主**：真正的组网与端口转发都在这里跑。
///
/// 注意：我们**不接管任何流量**。设置的网络参数只为了让系统认为隧道有效（无 included routes），
/// 数据面完全靠 EasyTier 在 loopback 上的监听与转发。
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var engine: TunnelEngine?
    private let logger = TunnelLogger()

    // MARK: - 启动

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let session = resolveSession(options: options) else {
            completionHandler(NSError(
                domain: "Terracotta",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "缺少会话参数，请在 App 里重新发起连接"]
            ))
            return
        }

        logger.log("扩展启动，角色=\(session.role.rawValue) 端口=\(session.minecraftPort)")

        let engine = TunnelEngine(session: session, logger: logger)
        self.engine = engine

        // 一个"空"隧道配置：给了地址与 MTU，但不放任何路由进去，因此不会劫持用户流量。
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: SessionConfig.hostVirtualIPv4)
        let ipv4 = NEIPv4Settings(addresses: ["172.31.77.1"], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = []
        ipv4.excludedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(error)
                return
            }
            if let error {
                self.logger.log("设置隧道参数失败：\(error.localizedDescription)")
                completionHandler(error)
                return
            }
            engine.start()
            // 立刻回成功，让状态变 connected（保活开始）；后续进度通过 providerMessage 回报。
            completionHandler(nil)
        }
    }

    private func resolveSession(options: [String: NSObject]?) -> SessionConfig? {
        // 优先 options（App 用 startVPNTunnel(options:) 时）
        if let data = options?["session"] as? Data,
           let session = try? JSONDecoder().decode(SessionConfig.self, from: data) {
            return session
        }
        // 其次 providerConfiguration
        if let proto = protocolConfiguration as? NETunnelProviderProtocol,
           let data = proto.providerConfiguration?["session"] as? Data,
           let session = try? JSONDecoder().decode(SessionConfig.self, from: data) {
            return session
        }
        return nil
    }

    // MARK: - 指令

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let command = (try? JSONSerialization.jsonObject(with: messageData) as? [String: String])?["cmd"] ?? "status"
        logger.log("收到指令 \(command)")

        switch command {
        case "stop":
            engine?.stop()
        case "retry":
            // 房客侧重新走一遍找房主流程
            engine?.stop()
            engine?.start()
        default:
            break
        }

        guard let status = engine?.snapshot() else {
            completionHandler?(try? JSONEncoder().encode(ProviderStatus.initial))
            return
        }
        completionHandler?(try? JSONEncoder().encode(status))
    }

    // MARK: - 停止

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("隧道停止，原因 \(reason.rawValue)")
        engine?.stop()
        engine = nil
        completionHandler()
    }

    // MARK: - 休眠 / 唤醒

    override func sleep(completionHandler: @escaping () -> Void) {
        // 系统休眠时不主动拆实例，只让上层知道状态；醒来后 EasyTier 会自己重连
        logger.log("系统休眠，保持实例")
        completionHandler()
    }
}
