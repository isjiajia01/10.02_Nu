import Foundation

/// Central dependency container for the app.
///
/// Goals:
/// - Keep long-lived shared services in one place.
/// - Avoid recreating network/location services across tabs.
/// - Provide lightweight factories for feature view models.
/// - Make future preview/test injection straightforward.
@MainActor
final class AppDependencies {
    private static var _current: AppDependencies?

    let apiService: APIServiceProtocol
    let locationManager: LocationManager
    let favoritesManager: FavoritesManager
    let diagnosticsStore: DiagnosticsStore
    let cacheStore: AppCacheStore
    let departureDelayStore: DepartureDelayStore

    static var current: AppDependencies? {
        _current
    }

    static var currentAPIService: APIServiceProtocol {
        _current?.apiService ?? RejseplanenAPIService()
    }

    static var currentLocationManager: LocationManager {
        _current?.locationManager ?? LocationManager()
    }

    static var currentFavoritesManager: FavoritesManager {
        _current?.favoritesManager ?? .shared
    }

    static var currentDiagnosticsStore: DiagnosticsStore {
        _current?.diagnosticsStore ?? .shared
    }

    static var currentCacheStore: AppCacheStore {
        _current?.cacheStore ?? .shared
    }

    init(
        apiService: APIServiceProtocol,
        locationManager: LocationManager,
        favoritesManager: FavoritesManager,
        diagnosticsStore: DiagnosticsStore,
        cacheStore: AppCacheStore,
        departureDelayStore: DepartureDelayStore
    ) {
        self.apiService = apiService
        self.locationManager = locationManager
        self.favoritesManager = favoritesManager
        self.diagnosticsStore = diagnosticsStore
        self.cacheStore = cacheStore
        self.departureDelayStore = departureDelayStore
        Self._current = self
    }

    static var live: AppDependencies {
        AppDependencies(
            apiService: RejseplanenAPIService(),
            locationManager: LocationManager(),
            favoritesManager: .shared,
            diagnosticsStore: .shared,
            cacheStore: .shared,
            departureDelayStore: DepartureDelayStore()
        )
    }

    static var preview: AppDependencies {
        AppDependencies(
            apiService: MockAPIService(),
            locationManager: LocationManager(),
            favoritesManager: .shared,
            diagnosticsStore: .shared,
            cacheStore: .shared,
            departureDelayStore: DepartureDelayStore()
        )
    }

    func makeWalkingETAService() -> WalkingETAServiceProtocol {
        WalkingETAService(
            apiService: apiService,
            overheadSeconds: AppConfig.walkETAOverheadSeconds
        )
    }

    func makeNearbyStationsViewModel() -> NearbyStationsViewModel {
        NearbyStationsViewModel(
            apiService: apiService,
            locationManager: locationManager
        )
    }

    func makeMapViewModel() -> MapViewModel {
        MapViewModel(
            apiService: apiService,
            locationManager: locationManager
        )
    }

    func makeDepartureBoardViewModel(
        stationId: String,
        walkingDestinations: [WalkingETADestination] = []
    ) -> DepartureBoardViewModel {
        DepartureBoardViewModel(
            stationId: stationId,
            walkingDestinations: walkingDestinations,
            apiService: apiService,
            locationManager: locationManager,
            walkingETAService: makeWalkingETAService()
        )
    }
}
