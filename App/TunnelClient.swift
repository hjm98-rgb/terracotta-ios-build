import Foundation
import NetworkExtension

/// 主 App 侧：管理 VPN 配置、启动/停止隧道、向 NE 发指令。
///
/// 刻意**不使用 App Group**：所有参数通过 `NETunnelProviderProtocol.providerConfiguration`
/// 传入，所有状态通过 `sendProviderMessage` 拉取。
/// 这样只需要 Network Extension 一个能力，个人证书签名时不会被 App Group 卡住。
@MainActor
final class TunnelClient {

    static let shared = TunnelClient()

    private(set) var manager: NETunnelProviderManager?
    private(set) var lastStatus: ProviderStatus = .initial

    // MARK: - 准备

    /// 加载（或首次创建）隧道配置。
    func prepare() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        if let existing = managers.first {
            manager = existing
        } else {
            let manager = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.providerBundleID
            proto.serverAddress = "Terracotta"
            proto.providerConfiguration = [:]
            manager.protocolConfiguration = proto
            manager.localizedDescription = "陶瓦联机"
            // 断网 / 切网络 / 重启后由系统自动拉起，这是后台不断线的关键之一
            manager.onDemandRules = [NEOnDemandRuleConnect()]
            manager.isOnDemandEnabled = true
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            self.manager = manager
        }
    }

    var isConnected: Bool {
        manager?.connection.status == .connected
    }

    var connectionStatus: NEVPNStatus {
        manager?.connection.status ?? .invalid
    }

    // MARK: - 启停

    func start(session: SessionConfig) async throws {
        guard let manager else { throw NSError(domain: "Terracotta", code: 1, userInfo: [NSLocalizedDescriptionKey: "隧道未准备好"]) }

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.providerBundleID
        proto.serverAddress = "Terracotta"
        proto.providerConfiguration = [
            "session": try JSONEncoder().encode(session)
        ]
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        manager.isOnDemandEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        try manager.connection.startVPNTunnel()
    }

    func stop() async {
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - 指令 / 状态

    /// 向 NE 发一条指令并等待回包。
    func send(_ command: ProviderCommand) async throws -> ProviderStatus? {
        guard let manager, manager.connection.status == .connected,
              let session = manager.connection as? NETunnelProviderSession
        else { return nil }

        let request = try JSONEncoder().encode(["cmd": command.rawValue])

        let data: Data? = try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard let data else { return nil }
        let status = try JSONDecoder().decode(ProviderStatus.self, from: data)
        lastStatus = status
        return status
    }

    static let providerBundleID = "com.doubao.terracotta.ios.tunnel"
}
