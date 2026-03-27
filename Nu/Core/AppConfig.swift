import Foundation

nonisolated struct RejseplanenAPISettings: Equatable {
    var baseURLString: String
    var accessID: String
    var apiVersion: String
    var authorizationBearerToken: String?

    var hasAccessID: Bool {
        !accessID.isEmpty
    }
}

/// 应用级配置。
///
/// 说明：
/// 1. 默认接入 Rejseplanen Labs REST API。
/// 2. 支持通过环境变量和构建设置覆写，便于本地/CI 分离密钥。
/// 3. 不再在源码中内置默认 access ID；缺失时由调用方显式处理。
nonisolated enum AppConfig {
    private static let defaultBaseURLString = "https://www.rejseplanen.dk/api"
    // Rejseplanen 当前生产接口默认走 `/api/<service>`；
    // 若后端环境需要显式版本，可通过 `REJSEPLANEN_API_VERSION` 覆盖。
    private static let defaultAPIVersion = ""
    private static let defaultWalkETACalibrationMultiplier = 1.15
    private static let defaultWalkETAOverheadSeconds = 60
    private static let defaultGeneralMinRequestInterval = 0.24
    private static let defaultPollingMinRequestInterval = 0.80
    private static let apiBaseURLDefaultsKey = "nu.rejseplanen.baseURL"
    private static let apiAccessIDDefaultsKey = "nu.rejseplanen.accessID"
    private static let apiVersionDefaultsKey = "nu.rejseplanen.version"
    private static let apiBearerTokenDefaultsKey = "nu.rejseplanen.bearerToken"

    static var currentAPISettings: RejseplanenAPISettings {
        resolvedAPISettings(
            environment: ProcessInfo.processInfo.environment,
            bundleInfo: Bundle.main.infoDictionary ?? [:],
            storage: UserDefaults.standard
        )
    }

    /// 支持通过环境变量覆写：`REJSEPLANEN_BASE_URL`。
    static var baseURLString: String {
        currentAPISettings.baseURLString
    }

    /// 支持通过环境变量或 Info.plist / Build Setting 覆写：`REJSEPLANEN_ACCESS_ID`。
    ///
    /// 默认不回退到硬编码值。仅在 XCTest 运行期间允许 test-only fallback；
    /// 其他情况下若未配置，返回空字符串，由上层抛出
    /// `missingAccessID` 或进行相应失败处理。
    static var accessID: String {
        currentAPISettings.accessID
    }

    /// 支持通过环境变量覆写：`REJSEPLANEN_API_VERSION`。
    static var apiVersion: String {
        currentAPISettings.apiVersion
    }

    /// 可选 Bearer token（若后端开启附加鉴权）。
    static var authorizationBearerToken: String? {
        currentAPISettings.authorizationBearerToken
    }

    /// 基础 URL 对象。
    static var baseURL: URL? {
        URL(string: baseURLString)
    }

    /// 鉴权参数是否有效。
    static var hasAccessID: Bool {
        currentAPISettings.hasAccessID
    }

    static func saveAPISettings(
        baseURLString: String,
        accessID: String,
        apiVersion: String,
        authorizationBearerToken: String?
    ) {
        saveAPISettings(
            baseURLString: baseURLString,
            accessID: accessID,
            apiVersion: apiVersion,
            authorizationBearerToken: authorizationBearerToken,
            storage: UserDefaults.standard
        )
    }

    static func saveAPISettings(
        baseURLString: String,
        accessID: String,
        apiVersion: String,
        authorizationBearerToken: String?,
        storage: UserDefaults
    ) {
        storage.set(sanitizedValue(baseURLString), forKey: apiBaseURLDefaultsKey)
        storage.set(sanitizedValue(accessID), forKey: apiAccessIDDefaultsKey)
        storage.set(sanitizedValue(apiVersion), forKey: apiVersionDefaultsKey)
        storage.set(sanitizedValue(authorizationBearerToken), forKey: apiBearerTokenDefaultsKey)
    }

    static func clearUserAPISettings() {
        clearUserAPISettings(storage: UserDefaults.standard)
    }

    static func clearUserAPISettings(storage: UserDefaults) {
        storage.removeObject(forKey: apiBaseURLDefaultsKey)
        storage.removeObject(forKey: apiAccessIDDefaultsKey)
        storage.removeObject(forKey: apiVersionDefaultsKey)
        storage.removeObject(forKey: apiBearerTokenDefaultsKey)
    }

    static var walkETACalibrationMultiplier: Double {
        let configured = sanitizedValue(ProcessInfo.processInfo.environment["NU_WALK_ETA_MULTIPLIER"])
        if let configured, let parsed = Double(configured) {
            return min(max(parsed, 1.0), 1.6)
        }
        return defaultWalkETACalibrationMultiplier
    }

    static var walkETAOverheadSeconds: Int {
        let configured = sanitizedValue(ProcessInfo.processInfo.environment["NU_WALK_ETA_OVERHEAD_SECONDS"])
        if let configured, let parsed = Int(configured) {
            return min(max(parsed, 0), 240)
        }
        return defaultWalkETAOverheadSeconds
    }

    static var generalMinRequestInterval: TimeInterval {
        let configured = sanitizedValue(ProcessInfo.processInfo.environment["NU_API_GENERAL_MIN_INTERVAL"])
        if let configured, let parsed = Double(configured) {
            return min(max(parsed, 0.05), 5)
        }
        return defaultGeneralMinRequestInterval
    }

    static var pollingMinRequestInterval: TimeInterval {
        let configured = sanitizedValue(ProcessInfo.processInfo.environment["NU_API_POLLING_MIN_INTERVAL"])
        if let configured, let parsed = Double(configured) {
            return min(max(parsed, 0.05), 10)
        }
        return defaultPollingMinRequestInterval
    }

    // MARK: - Private

    static func resolvedAPISettings(
        environment: [String: String],
        bundleInfo: [String: Any],
        storage: UserDefaults
    ) -> RejseplanenAPISettings {
        let persistedBaseURL = sanitizedValue(storage.string(forKey: apiBaseURLDefaultsKey))
        let persistedAccessID = sanitizedValue(storage.string(forKey: apiAccessIDDefaultsKey))
        let persistedAPIVersion = sanitizedValue(storage.string(forKey: apiVersionDefaultsKey))
        let persistedBearerToken = sanitizedValue(storage.string(forKey: apiBearerTokenDefaultsKey))

        let baseURLString = sanitizedValue(environment["REJSEPLANEN_BASE_URL"])
            ?? persistedBaseURL
            ?? defaultBaseURLString
        let accessID = resolvedAccessID(
            environment: environment,
            bundleInfo: bundleInfo,
            persistedAccessID: persistedAccessID
        ) ?? ""
        let apiVersion = sanitizedValue(environment["REJSEPLANEN_API_VERSION"])
            ?? persistedAPIVersion
            ?? defaultAPIVersion
        let authorizationBearerToken = sanitizedValue(environment["REJSEPLANEN_AUTH_BEARER"])
            ?? persistedBearerToken

        return RejseplanenAPISettings(
            baseURLString: baseURLString,
            accessID: accessID,
            apiVersion: apiVersion,
            authorizationBearerToken: authorizationBearerToken
        )
    }

    private static func resolvedAccessID(
        environment: [String: String],
        bundleInfo: [String: Any],
        persistedAccessID: String?
    ) -> String? {
        if let envValue = sanitizedValue(environment["REJSEPLANEN_ACCESS_ID"]) {
            return envValue
        }

        if let persistedAccessID {
            return persistedAccessID
        }

        if let bundleRaw = bundleInfo["REJSEPLANEN_ACCESS_ID"] {
            return sanitizedValue(String(describing: bundleRaw))
        }

        if environment["XCTestSessionIdentifier"] != nil {
            return "xctest-access-id"
        }

        return nil
    }

    static func sanitizedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Reject unresolved Xcode build-setting placeholders such as:
        // - $(REJSEPLANEN_ACCESS_ID)
        // - ${REJSEPLANEN_ACCESS_ID}
        // and similar unresolved variable references.
        if trimmed.hasPrefix("$(") || trimmed.hasPrefix("${") {
            return nil
        }

        // Reject obvious placeholder/demo values.
        let lowered = trimmed.lowercased()
        if lowered == "<your key>" || lowered == "your_key" || lowered == "changeme" {
            return nil
        }

        return trimmed
    }
}
