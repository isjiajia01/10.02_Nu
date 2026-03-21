import Foundation

/// Result of loading a station's departure board.
///
/// This keeps transport concerns out of the ViewModel while preserving the
/// information the UI needs to decide between success, stale-cache fallback,
/// and terminal failure.
enum DepartureBoardLoadOutcome: Equatable {
    case success(
        departures: [Departure],
        isDataStale: Bool,
        toastMessage: String?
    )
    case failure(message: String)
}

/// Service responsible for fetching, normalizing, enriching, and caching
/// departure board data for a single station.
struct DepartureBoardLoader {
    private let stationId: String
    private let apiService: APIServiceProtocol
    private let orService: ORService
    private let cacheStore: AppCacheStore
    private let cacheMaxAge: TimeInterval

    private var cacheKey: String {
        "departure_cache_\(stationId)"
    }

    init(
        stationId: String,
        apiService: APIServiceProtocol,
        orService: ORService = ORService(),
        cacheStore: AppCacheStore = .shared,
        cacheMaxAge: TimeInterval = 90
    ) {
        self.stationId = stationId
        self.apiService = apiService
        self.orService = orService
        self.cacheStore = cacheStore
        self.cacheMaxAge = cacheMaxAge
    }

    func load() async -> DepartureBoardLoadOutcome {
        do {
            let fetched = try await apiService.fetchDepartures(for: stationId)
            let normalized = normalize(fetched)
            let enriched = normalized.map { orService.enrich($0) }

            cacheStore.save(enriched, key: cacheKey)

            return .success(
                departures: enriched,
                isDataStale: false,
                toastMessage: nil
            )
        } catch {
            let message = AppErrorPresenter.message(for: error, context: .departures)

            if let cached = cacheStore.load([Departure].self, key: cacheKey, maxAge: cacheMaxAge) {
                let enrichedCached = normalize(cached.value).map { orService.enrich($0) }
                return .success(
                    departures: enrichedCached,
                    isDataStale: true,
                    toastMessage: L10n.tr("departures.cache.toast")
                )
            }

            return .failure(message: message)
        }
    }

    private func normalize(_ departures: [Departure]) -> [Departure] {
        Array(
            Dictionary(
                departures.map { (($0.journeyRef ?? $0.id), $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )
        .sorted { lhs, rhs in
            (lhs.minutesUntilDepartureRaw ?? .max) < (rhs.minutesUntilDepartureRaw ?? .max)
        }
    }
}
