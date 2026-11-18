import Foundation

/// NE 进程内的日志环形缓冲，同时上报给主 App。
final class TunnelLogger {
    private let queue = DispatchQueue(label: "terracotta.log")
    private var buffer: [String] = []
    private let capacity = 200

    func log(_ message: String) {
        let stamp = Self.formatter.string(from: Date())
        queue.async {
            self.buffer.append("[\(stamp)] \(message)")
            if self.buffer.count > self.capacity {
                self.buffer.removeFirst(self.buffer.count - self.capacity)
            }
        }
        appendEvent(message)
    }

    var snapshot: [String] {
        queue.sync { buffer }
    }

    private func appendEvent(_ message: String) {
        EasyTierIOS.appendDiagnosticEvent(message)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
