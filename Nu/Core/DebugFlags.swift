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

    /// 是否打印 journeypos 关键采样日志。
    /// 开启方式：`NU_DEBUG_JOURNEYPOS=1` 或 `UserDefaults.standard.set(true, forKey: "nu_debug_journeypos")`
    static var journeyPosSamplingEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["NU_DEBUG_JOURNEYPOS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if env == "1" || env == "true" || env == "yes" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "nu_debug_journeypos")
    }

    /// P0-5: 是否输出追踪性能计数器（每 30s 汇总日志）。
    /// 开启方式：`NU_DEBUG_TRACKING_PERF=1` 或 `UserDefaults.standard.set(true, forKey: "nu_debug_tracking_perf")`
    static var trackingPerfLoggingEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["NU_DEBUG_TRACKING_PERF"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if env == "1" || env == "true" || env == "yes" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "nu_debug_tracking_perf")
    }
}
#endif
