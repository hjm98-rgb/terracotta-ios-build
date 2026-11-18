import Foundation

/// 端口探测：只用来找本机正在监听的 MC 局域网端口。
enum IPv4Socket {

    static func canConnect(port: Int, host: String = "127.0.0.1", timeout: TimeInterval = 0.3) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr(host)

        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
