import Foundation

/// 统一的网络层错误定义。
///
/// 目标：
/// - 将系统错误（URLSession/HTTP/解码）映射为业务可理解的错误。
/// - 便于 ViewModel 做用户提示（Toast/Alert）以及重试策略。
enum APIError: Error, LocalizedError {
    case invalidBaseURL
    case missingAccessID
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case forbidden
    case serverMessage(String)
    case decodingFailed
    case network(Error)
    case unknown

    /// 中文可读描述，可直接用于界面提示。
    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return L10n.tr("error.invalidBaseURL")
        case .missingAccessID:
            return L10n.tr("error.missingAccessID")
        case .invalidRequest:
            return L10n.tr("error.invalidRequest")
        case .invalidResponse:
            return L10n.tr("error.invalidResponse")
        case .httpStatus(let code):
            return L10n.tr("error.httpStatus", code)
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return L10n.tr("error.rateLimitedWithRetry", Int(retryAfter.rounded(.up)))
            }
            return L10n.tr("error.rateLimited")
        case .unauthorized:
            return L10n.tr("error.unauthorized")
        case .forbidden:
            return L10n.tr("error.forbidden")
        case .serverMessage(let message):
            return L10n.tr("error.serverMessage", message)
        case .decodingFailed:
            return L10n.tr("error.decodingFailed")
        case .network(let error):
            return L10n.tr("error.network", error.localizedDescription)
        case .unknown:
            return L10n.tr("error.unknown")
        }
    }
}
