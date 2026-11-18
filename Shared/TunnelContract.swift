import Foundation

/// 主 App → NE 的指令
enum ProviderCommand: String {
    /// 拉一次状态与日志
    case status
    /// 主动停止
    case stop
    /// 手动重试一次房客侧「找房主 + 加转发」
    case retry
}

/// NE → 主 App 的状态回报
struct ProviderStatus: Codable {
    enum Phase: String, Codable {
        case idle
        case starting
        case negotiating      // 打洞中
        case discoveringPeer  // 找房主
        case forwarding       // 加端口转发
        case ready
        case failed
        case stopped
    }

    var phase: Phase
    var detail: String
    /// 房客可用地址，形如 `127.0.0.1:25565`
    var connectAddress: String?
    var hostPort: Int?
    var natType: String?
    var peerCount: Int
    var logs: [String]
    var errorText: String?
    var updatedAt: TimeInterval

    static let initial = ProviderStatus(
        phase: .idle, detail: "未启动", connectAddress: nil, hostPort: nil,
        natType: nil, peerCount: 0, logs: [], errorText: nil, updatedAt: 0
    )
}
