import Foundation

/// 角色
enum TunnelRole: String, Codable {
    case host
    case guest
}

/// 一次联机会话的完整描述，主 App 与 NE 共用。
struct SessionConfig: Codable, Equatable {
    var role: TunnelRole
    /// 房主：MC 局域网端口；房客：连接后才知道，先留空
    var minecraftPort: Int
    var inviteCode: String
    /// 自定义中转节点（留空则用内置公共节点）
    var publicNodes: [String]
    /// 实例名，用于多实例管理与日志区分
    var instanceName: String

    static let defaultPublicNodes = [
        "tcp://public.easytier.top:11010",
        "tcp://public2.easytier.cn:54321",
        "https://etnode.zkitefly.eu.org/node1",
        "https://etnode.zkitefly.eu.org/node2",
    ]

    /// 房主 hostname 前缀：`scaffolding-mc-server-<端口>`，房客靠它拿端口
    static let hostHostnamePrefix = "scaffolding-mc-server-"

    /// 房主虚拟 IP 固定值，与 PC 端一致
    static let hostVirtualIPv4 = "10.144.144.1"
}

/// 生成 EasyTier 实例的 TOML 配置。
///
/// 关键点：两端都用 `no_tun = true`，iOS 不需要 TUN，靠 loopback 监听 + 端口转发完成数据面。
enum EasyTierConfigBuilder {

    static func hostTOML(code: InviteCode, mcPort: Int, nodes: [String], instanceName: String) -> String {
        let nodeList = nodes.isEmpty ? SessionConfig.defaultPublicNodes : nodes
        let peers = nodeList.map { "[[peer]]\nuri = \"\($0)\"\n" }.joined(separator: "\n")

        return """
        instance_name = "\(instanceName)"
        hostname = "\(SessionConfig.hostHostnamePrefix)\(mcPort)"
        ipv4 = "\(SessionConfig.hostVirtualIPv4)"
        listeners = ["tcp://0.0.0.0:0", "udp://0.0.0.0:0"]
        rpc_portal = "127.0.0.1:0"

        [network_identity]
        network_name = "\(code.networkName)"
        network_secret = "\(code.networkSecret)"

        [flags]
        no_tun = true
        latency_first = true
        enable_kcp_proxy = true
        multi_thread = true
        enable_encryption = true
        p2p_only = true
        relay_network_whitelist = "\(mcPort)"

        \(peers)
        """
    }

    static func guestTOML(
        code: InviteCode,
        nodes: [String],
        instanceName: String,
        forward: (listen: Int, hostPort: Int)? = nil
    ) -> String {
        let nodeList = nodes.isEmpty ? SessionConfig.defaultPublicNodes : nodes
        let peers = nodeList.map { "[[peer]]\nuri = \"\($0)\"\n" }.joined(separator: "\n")

        var forwardBlock = ""
        if let forward {
            // TCP + UDP 各一条：UDP 是给 SimpleVoiceChat 这类模组用的
            forwardBlock = """

            [[port_forward]]
            bind_addr = "0.0.0.0:\(forward.listen)"
            dst_addr = "\(SessionConfig.hostVirtualIPv4):\(forward.hostPort)"
            proto = "tcp"

            [[port_forward]]
            bind_addr = "0.0.0.0:\(forward.listen)"
            dst_addr = "\(SessionConfig.hostVirtualIPv4):\(forward.hostPort)"
            proto = "udp"
            """
        }

        return """
        instance_name = "\(instanceName)"
        hostname = "terracotta-ios-guest"
        dhcp = true
        listeners = ["tcp://0.0.0.0:0", "udp://0.0.0.0:0"]
        rpc_portal = "127.0.0.1:0"

        [network_identity]
        network_name = "\(code.networkName)"
        network_secret = "\(code.networkSecret)"

        [flags]
        no_tun = true
        latency_first = true
        enable_kcp_proxy = true
        multi_thread = true
        enable_encryption = true
        p2p_only = true
        \(forwardBlock)
        \(peers)
        """
    }

    /// 动态加转发用的 PatchConfig RPC 报文（主路径）。
    /// 字段名如与服务端不一致，TunnelEngine 会自动降级为「带 port_forward 重启实例」。
    static func patchConfigPayload(instanceName: String, listen: Int, hostPort: Int) -> String {
        """
        {"instance":{"name":"\(instanceName)"},
         "patch_config":{"port_forward":[
           {"bind_addr":"0.0.0.0:\(listen)","dst_addr":"\(SessionConfig.hostVirtualIPv4):\(hostPort)","proto":"tcp"},
           {"bind_addr":"0.0.0.0:\(listen)","dst_addr":"\(SessionConfig.hostVirtualIPv4):\(hostPort)","proto":"udp"}
         ]}}
        """
    }
}
