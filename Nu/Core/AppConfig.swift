import Foundation

/// 应用级配置。
///
/// 说明：
/// 1. 默认接入 Rejseplanen Labs REST API。
/// 2. 支持通过环境变量覆盖，便于本地/CI 分离密钥。
enum AppConfig {
    private static let defaultBaseURLString = "https://www.rejseplanen.dk/api"
    // Rejseplanen 当前生产接口默认走 `/api/<service>`；
    // 若后端环境需要显式版本，可通过 `REJSEPLANEN_API_VERSION` 覆盖。
    private static let defaultAPIVersion = ""
    private static let defaultAccessID = ""

    /// 支持通过环境变量覆写：`REJSEPLANEN_BASE_URL`。
    static var baseURLString: String {
        let configured = ProcessInfo.processInfo.environment["REJSEPLANEN_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return defaultBaseURLString
    }

    /// 支持通过环境变量覆写：`REJSEPLANEN_ACCESS_ID`。
    static var accessID: String {
        let configured = ProcessInfo.processInfo.environment["REJSEPLANEN_ACCESS_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "REJSEPLANEN_ACCESS_ID") as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return defaultAccessID
    }

    /// 支持通过环境变量覆写：`REJSEPLANEN_API_VERSION`。
    static var apiVersion: String {
        let configured = ProcessInfo.processInfo.environment["REJSEPLANEN_API_VERSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return defaultAPIVersion
    }

    /// 可选 Bearer token（若后端开启附加鉴权）。
    static var authorizationBearerToken: String? {
        let configured = ProcessInfo.processInfo.environment["REJSEPLANEN_AUTH_BEARER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return nil
    }

    /// 基础 URL 对象。
    static var baseURL: URL? {
        URL(string: baseURLString)
    }

    /// 鉴权参数是否有效。
    static var hasAccessID: Bool {
        !accessID.isEmpty
    }
}
