import Foundation
import UIKit
import NetworkExtension

/// 全局状态与动作。UI 只认这一个对象。
@MainActor
final class AppModel: ObservableObject {

    enum Route: Hashable {
        case host
        case join
        case room
        case log
    }

    @Published var path: [Route] = []
    @Published var status: ProviderStatus = .initial
    @Published var isBusy = false
    @Published var alertText: String?

    // 房主侧
    @Published var mcPort = "25565"
    @Published var hostCode: String = ""

    // 房客侧
    @Published var guestCodeInput = ""
    @Published var customNodeInput = ""

    // 最近一次会话，供房间页展示
    @Published var currentRole: TunnelRole = .guest
    @Published var currentCode: String = ""

    private var pollTask: Task<Void, Never>?

    var isConnected: Bool {
        switch status.phase {
        case .ready, .negotiating, .discoveringPeer, .forwarding, .starting: return true
        default: return false
        }
    }

    var phaseText: String {
        switch status.phase {
        case .idle: return "未连接"
        case .starting: return "启动组网核心…"
        case .negotiating: return "P2P 打洞中…"
        case .discoveringPeer: return "已组网 · 正在找房主"
        case .forwarding: return "正在建立通道…"
        case .ready: return "已连接"
        case .failed: return "连接失败"
        case .stopped: return "已停止"
        }
    }

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    // MARK: - 生命周期

    func bootstrap() async {
        do {
            try await TunnelClient.shared.prepare()
        } catch {
            alertText = "隧道配置初始化失败：\(error.localizedDescription)"
        }
        await refresh()
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        // send() 返回 Optional，这里用 do/catch 明确处理，不依赖 try? 的扁平化行为
        do {
            guard let fetched = try await TunnelClient.shared.send(.status) else { return }
            status = fetched
            if fetched.phase == .ready, currentRole == .guest, mcPort.isEmpty, let hostPort = fetched.hostPort {
                mcPort = String(hostPort)
            }
        } catch {
            // 隧道没起来时 send 会返回 nil，这里静默即可
        }
    }

    // MARK: - 房主

    func startHost() async {
        guard let port = Int(mcPort), (1...65535).contains(port) else {
            alertText = "端口不合法，请输入 1–65535 之间的数字"
            return
        }
        guard let invite = hostCode.isEmpty ? InviteCode.random() : InviteCode.parse(hostCode) else {
            alertText = "房间码无效，请重新生成"
            return
        }
        hostCode = invite.code
        currentRole = .host
        currentCode = invite.code
        await start(session: SessionConfig(
            role: .host,
            minecraftPort: port,
            inviteCode: invite.code,
            publicNodes: nodes(),
            instanceName: "terracotta-ios-host"
        ))
        path.append(.room)
    }

    func regenerateCode() {
        hostCode = InviteCode.random().code
    }

    // MARK: - 房客

    func startGuest() async {
        guard let invite = InviteCode.parse(guestCodeInput) else {
            alertText = "邀请码无效。正确格式：U/XXXX-XXXX-XXXX-XXXX（自动校验 7 的整除性）"
            return
        }
        currentRole = .guest
        currentCode = invite.code
        await start(session: SessionConfig(
            role: .guest,
            minecraftPort: 0,
            inviteCode: invite.code,
            publicNodes: nodes(),
            instanceName: "terracotta-ios-guest"
        ))
        path.append(.room)
    }

    private func nodes() -> [String] {
        let custom = customNodeInput
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return custom.isEmpty ? SessionConfig.defaultPublicNodes : custom
    }

    // MARK: - 通用启停

    private func start(session: SessionConfig) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await TunnelClient.shared.start(session: session)
            status = .initial
            // 等系统把扩展拉起来（一般 1–3 秒）
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if TunnelClient.shared.connectionStatus == .connected { break }
            }
            await refresh()
        } catch {
            alertText = "启动失败：\(error.localizedDescription)"
        }
    }

    func stop() async {
        await TunnelClient.shared.stop()
        status = .initial
    }

    func copy(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        UIPasteboard.general.string = clean
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// MC Java 版连接地址：IP 在前，冒号，端口在后
    var connectAddressText: String {
        if let address = status.connectAddress, !address.isEmpty { return address }
        return "127.0.0.1:\(mcPort)"
    }
}
