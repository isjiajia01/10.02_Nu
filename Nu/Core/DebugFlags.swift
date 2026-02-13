import Foundation

#if DEBUG
enum DebugFlags {
    /// 是否打印 Rejseplanen 发车实时字段诊断日志。
    /// 开启方式（任一）：
    /// 1) Xcode Scheme -> Run -> Arguments -> Environment:
    ///    `NU_DEBUG_RT_FIELDS=1`
    /// 2) 代码中执行：
    ///    `UserDefaults.standard.set(true, forKey: "nu_debug_rt_fields")`
    static var realtimeFieldLoggingEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["NU_DEBUG_RT_FIELDS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if env == "1" || env == "true" || env == "yes" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "nu_debug_rt_fields")
    }
}
#endif
