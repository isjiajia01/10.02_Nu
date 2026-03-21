import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var stationGroups: [StationGroupModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var focusCoordinate: CLLocationCoordinate2D?
    @Published private(set) var focusToken: Int = 0
    @Published var selectedGroup: StationGroupModel?
    @Published private(set) var showSearchAreaButton = false
    @Published private(set) var authStatus: CLAuthorizationStatus
    @Published private(set) var isLocating = true

    var isLocationDenied: Bool {
        authStatus == .denied || authStatus == .restricted
    }

    private let locationManager: LocationManaging
    private let apiService: APIServiceProtocol

    private let fallbackLongitude = 12.568337
    private let fallbackLatitude = 55.676098

    private var hasStarted = false
    private var hasReceivedFirstFix = false
    private var hasReceivedStableFix = false
    private var hasShownFallbackToast = false

    private var lastRefreshQuery: MapRefreshQuery?
    private var pendingQuery: MapRefreshQuery?

    private var debounceTask: Task<Void, Never>?
    private var inFlightFetchTask: Task<Void, Never>?
    private var stableRefreshTask: Task<Void, Never>?
    private var fallbackToastTask: Task<Void, Never>?

    init(
        apiService: APIServiceProtocol = RejseplanenAPIService(),
        locationManager: LocationManaging
    ) {
        self.apiService = apiService
        self.locationManager = locationManager
        self.authStatus = locationManager.authorizationStatus
    }

    deinit {
        debounceTask?.cancel()
        inFlightFetchTask?.cancel()
        stableRefreshTask?.cancel()
        fallbackToastTask?.cancel()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        errorMessage = nil
        isLocating = true
        authStatus = locationManager.authorizationStatus

        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        fallbackToastTask?.cancel()
        fallbackToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.hasReceivedFirstFix, !self.hasShownFallbackToast else { return }

            if !self.isLocationDenied {
                self.hasShownFallbackToast = true
                self.errorMessage = L10n.tr("map.locationFallback")
            }

            self.isLocating = false
            await self.loadStations(
                coordX: self.fallbackLongitude,
                coordY: self.fallbackLatitude,
                isFallback: true
            )
        }
    }

    func stop() {
        debounceTask?.cancel()
        inFlightFetchTask?.cancel()
        stableRefreshTask?.cancel()
        fallbackToastTask?.cancel()
    }

    func clearError() {
        errorMessage = nil
    }

    func handleAuthorizationUpdate(_ auth: CLAuthorizationStatus) {
        authStatus = auth
    }

    func handleLocationUpdate(_ location: CLLocation?) {
        guard let location else { return }

        if !hasReceivedFirstFix, isFirstFix(location) {
            hasReceivedFirstFix = true
            isLocating = false
            fallbackToastTask?.cancel()
            errorMessage = nil

            focusCoordinate = location.coordinate
            focusToken += 1

            Task { [weak self] in
                await self?.loadStationsFromLocation(location)
            }

            stableRefreshTask?.cancel()
            stableRefreshTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard !self.hasReceivedStableFix else { return }
            }
        }

        if !hasReceivedStableFix, isStableFix(location) {
            hasReceivedStableFix = true
            stableRefreshTask?.cancel()
            fallbackToastTask?.cancel()
            errorMessage = nil

            Task { [weak self] in
                await self?.loadStationsFromLocation(location)
            }
        }
    }

    func handleViewportChange(region: MKCoordinateRegion, userGesture: Bool) {
        guard userGesture else { return }

        let nextQuery = MapRefreshQuery.from(center: region.center, span: region.span)
        guard shouldRefresh(from: lastRefreshQuery, to: nextQuery) else { return }

        pendingQuery = nextQuery
        showSearchAreaButton = true
        scheduleAutoRefresh(with: nextQuery)
    }

    func triggerManualSearch() {
        guard let query = pendingQuery else { return }
        debounceTask?.cancel()

        Task { [weak self] in
            await self?.runViewportRefresh(query)
        }
    }

    func selectGroup(_ group: StationGroupModel) {
        selectedGroup = group
    }

    private func scheduleAutoRefresh(with query: MapRefreshQuery) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.runViewportRefresh(query)
        }
    }

    private func runViewportRefresh(_ query: MapRefreshQuery) async {
        inFlightFetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        showSearchAreaButton = false

        inFlightFetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try Task.checkCancellation()

                let fetched = try await self.apiService.fetchNearbyStops(
                    coordX: query.center.longitude,
                    coordY: query.center.latitude,
                    radiusMeters: query.radiusMeters,
                    maxNo: query.maxNo
                )
                guard !Task.isCancelled else { return }

                self.stationGroups = StationGrouping.buildGroups(fetched)
                self.lastRefreshQuery = query
                self.pendingQuery = nil
                self.isLoading = false
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.errorMessage = AppErrorPresenter.message(for: error, context: .map)
                self.isLoading = false
            }
        }
    }

    private func loadStationsFromLocation(_ location: CLLocation) async {
        if isLikelyInDenmark(location) {
            await loadStations(
                coordX: location.coordinate.longitude,
                coordY: location.coordinate.latitude,
                isFallback: false
            )
        } else {
            await loadStations(
                coordX: fallbackLongitude,
                coordY: fallbackLatitude,
                isFallback: true
            )
            if !hasShownFallbackToast {
                hasShownFallbackToast = true
                errorMessage = L10n.tr("map.locationFallback")
            }
        }
    }

    private func loadStations(coordX: Double, coordY: Double, isFallback: Bool) async {
        isLoading = true

        do {
            let initialQuery = MapRefreshQuery.from(
                center: CLLocationCoordinate2D(latitude: coordY, longitude: coordX),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )

            let fetched = try await apiService.fetchNearbyStops(
                coordX: coordX,
                coordY: coordY,
                radiusMeters: initialQuery.radiusMeters,
                maxNo: initialQuery.maxNo
            )

            stationGroups = StationGrouping.buildGroups(fetched)
            lastRefreshQuery = initialQuery
            pendingQuery = nil
            showSearchAreaButton = false

            if !isFallback {
                errorMessage = nil
            }

            if let first = stationGroups.first?.bestEntrance() {
                focusCoordinate = CLLocationCoordinate2D(
                    latitude: first.latitude,
                    longitude: first.longitude
                )
                focusToken += 1
            }
        } catch {
            errorMessage = AppErrorPresenter.message(for: error, context: .map)
            if stationGroups.isEmpty {
                stationGroups = []
            }
        }

        isLoading = false
    }

    private func shouldRefresh(from previous: MapRefreshQuery?, to next: MapRefreshQuery) -> Bool {
        guard let previous else { return true }
        return previous.centerDistanceMeters(to: next) > 200
            || previous.spanDeltaRatio(to: next) > 0.30
    }

    private func isFirstFix(_ location: CLLocation) -> Bool {
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return false }
        guard !(coord.latitude == 0 && coord.longitude == 0) else { return false }
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 5000 else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) < 60 else { return false }
        return true
    }

    private func isStableFix(_ location: CLLocation) -> Bool {
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return false }
        guard !(coord.latitude == 0 && coord.longitude == 0) else { return false }
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 1000 else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) < 30 else { return false }
        return true
    }

    private func isLikelyInDenmark(_ location: CLLocation) -> Bool {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return (54.0...58.0).contains(lat) && (7.0...16.5).contains(lon)
    }
}

struct MapRefreshQuery: Equatable {
    let center: CLLocationCoordinate2D
    let latitudeDelta: Double
    let longitudeDelta: Double
    let radiusMeters: Int
    let maxNo: Int

    static func from(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MapRefreshQuery {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let latEdge = CLLocation(
            latitude: center.latitude + span.latitudeDelta / 2,
            longitude: center.longitude
        )
        let lonEdge = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude + span.longitudeDelta / 2
        )

        let radius = Int(max(centerLocation.distance(from: latEdge), centerLocation.distance(from: lonEdge)))
        let clampedRadius = min(1500, max(300, radius))
        let maxNo = min(80, max(30, Int(30 + (Double(clampedRadius - 300) / 1200.0) * 50.0)))

        return MapRefreshQuery(
            center: center,
            latitudeDelta: span.latitudeDelta,
            longitudeDelta: span.longitudeDelta,
            radiusMeters: clampedRadius,
            maxNo: maxNo
        )
    }

    func centerDistanceMeters(to other: MapRefreshQuery) -> Double {
        let a = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let b = CLLocation(latitude: other.center.latitude, longitude: other.center.longitude)
        return a.distance(from: b)
    }

    func spanDeltaRatio(to other: MapRefreshQuery) -> Double {
        let latRatio = abs(other.latitudeDelta - latitudeDelta) / max(latitudeDelta, 0.0001)
        let lonRatio = abs(other.longitudeDelta - longitudeDelta) / max(longitudeDelta, 0.0001)
        return max(latRatio, lonRatio)
    }

    static func == (lhs: MapRefreshQuery, rhs: MapRefreshQuery) -> Bool {
        lhs.center.latitude == rhs.center.latitude
            && lhs.center.longitude == rhs.center.longitude
            && lhs.latitudeDelta == rhs.latitudeDelta
            && lhs.longitudeDelta == rhs.longitudeDelta
            && lhs.radiusMeters == rhs.radiusMeters
            && lhs.maxNo == rhs.maxNo
    }
}
