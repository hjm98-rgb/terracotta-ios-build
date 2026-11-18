import Foundation

/// EasyTier 官方 iOS 静态库（libeasytier_ios.a）的 Swift 封装。
///
/// 该库**不创建 TUN / 不接管路由**，只做两件事：
///   1. 按 TOML 配置拉起 / 停止 EasyTier 实例（组网、打洞、加密）
///   2. 通过管理 RPC 动态打端口转发补丁（loopback 监听 → 虚拟网内地址）
///
/// 所有函数都是线程安全的；last-error 是 thread-local，必须在出错的那个线程上取。
enum EasyTierIOSError: LocalizedError {
    case ffi(String)

    var errorDescription: String? {
        switch self {
        case .ffi(let message): return message
        }
    }
}

enum EasyTierIOS {

    // MARK: - 实例生命周期

    /// 用 TOML 配置启动一个实例。`instance_name` 必须在已启动实例中唯一。
    @discardableResult
    static func runInstance(toml: String) throws -> Int32 {
        var rc: Int32 = -1
        toml.withCString { pointer in
            rc = easytier_ios_run_instance(pointer)
        }
        if rc != 0 { throw EasyTierIOSError.ffi(lastError() ?? "run_instance 失败") }
        return rc
    }

    /// 只保留指定实例，其余全部停止。传空即全停。
    static func retainInstances(_ names: [String]) throws {
        let json = try JSONSerialization.data(withJSONObject: names, options: [])
        let text = String(data: json, encoding: .utf8) ?? "[]"
        var rc: Int32 = -1
        text.withCString { rc = easytier_ios_retain_instances($0) }
        if rc != 0 { throw EasyTierIOSError.ffi(lastError() ?? "retain_instances 失败") }
    }

    /// 停止单个实例；名字不存在时是无操作。
    static func deleteInstance(_ name: String) throws {
        var rc: Int32 = -1
        name.withCString { rc = easytier_ios_delete_instance($0) }
        if rc != 0 { throw EasyTierIOSError.ffi(lastError() ?? "delete_instance 失败") }
    }

    static func stopAll() {
        var rc: Int32 = -1
        "[]".withCString { rc = easytier_ios_retain_instances($0) }
        _ = rc
    }

    // MARK: - 状态查询

    /// 返回 { 实例名: 运行信息 } 的 JSON 字典。
    static func collectNetworkInfos(maxLength: Int = 8) -> [String: Any] {
        guard let cString = easytier_ios_collect_network_infos(Int32(maxLength)) else { return [:] }
        defer { easytier_ios_free_string(cString) }
        let text = String(cString: cString)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: - 管理 RPC

    /// 走 EasyTier 的管理 RPC（protobuf JSON）。iOS 端加端口转发的主路径。
    static func callJSONRPC(service: String, method: String, payload: String) throws -> [String: Any] {
        var result: UnsafeMutablePointer<CChar>?

        service.withCString { svc in
            method.withCString { mtd in
                payload.withCString { body in
                    result = easytier_ios_call_json_rpc(svc, mtd, body)
                }
            }
        }

        guard let pointer = result else {
            throw EasyTierIOSError.ffi(lastError() ?? "RPC \(service)/\(method) 失败")
        }
        defer { easytier_ios_free_string(pointer) }

        let text = String(cString: pointer)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ["_raw": text] }
        return object
    }

    // MARK: - 诊断日志

    static func configureDiagnosticLogging(directory: String, enabled: Bool) {
        directory.withCString { dir in
            _ = easytier_ios_configure_diagnostic_logging(dir, enabled ? 1 : 0)
        }
    }

    static func appendDiagnosticEvent(_ message: String) {
        message.withCString { _ = easytier_ios_append_diagnostic_event($0) }
    }

    static func flushDiagnosticLogging() {
        _ = easytier_ios_flush_diagnostic_logging()
    }

    static func lastError() -> String? {
        guard let cString = easytier_ios_last_error() else { return nil }
        defer { easytier_ios_free_string(cString) }
        return String(cString: cString)
    }
}
