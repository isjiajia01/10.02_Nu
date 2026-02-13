import Foundation

enum AppErrorContext {
    case stations
    case departures
    case journeyDetail
    case map

    var fallbackKey: String {
        switch self {
        case .stations: return "stations.fetchFailed"
        case .departures: return "departures.fetchFailed"
        case .journeyDetail: return "journeyDetail.fetchFailed"
        case .map: return "map.loadFailed.description"
        }
    }
}

enum AppErrorPresenter {
    static func message(for error: Error, context: AppErrorContext) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .network:
                return L10n.tr("error.offline")
            case .httpStatus(let code) where code >= 500:
                return L10n.tr("error.apiUnavailable")
            case .httpStatus:
                return L10n.tr("error.badRequest")
            case .decodingFailed:
                return L10n.tr("error.parsing")
            case .serverMessage(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return L10n.tr(context.fallbackKey)
                }
                return L10n.tr("error.serverMessage", trimmed)
            default:
                return apiError.errorDescription ?? L10n.tr(context.fallbackKey)
            }
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return L10n.tr(context.fallbackKey)
    }
}
