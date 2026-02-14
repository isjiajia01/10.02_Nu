import Foundation
import Combine
import CoreLocation

/// Departure board ViewModel.
///
/// Responsibilities:
/// - Fetch and maintain departure list for a station.
/// - Expose loading/error state to SwiftUI.
/// - Own `departureDelayMinutes` (user input) and walk ETA (system).
/// - Delegate all catch-probability logic to `DecisionPolicy`.
@MainActor
final class DepartureBoardViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case loading
        case success
        case empty
        case error(String)
    }

    @Published private(set) var departures: [Departure] = []
    @Published private(set) var state: ViewState = .idle
    @Published private(set) var isDataStale: Bool = false
    @Published var toastMessage: String?
    @Published private(set) var walkingETAState: WalkingETAState = .idle

    // Walk ETA (system-estimated, read-only for user)
    @Published private(set) var walkMinutes: Double = 5.0
    @Published private(set) var walkTimeSource: WalkTimeSource = .estimated
    @Published private(set) var walkP10Minutes: Double = 3
    @Published private(set) var walkP90Minutes: Double = 9

    // Departure delay (user input: "I'll leave in N min")
    @Published var departureDelayMinutes: Int = 0

    // Presets
    @Published private(set) var activePreset: WalkPreset?
    @Published private(set) var isAtStationOverride: Bool = false

    private let apiService: APIServiceProtocol
    private let stationId: String
    private let locationManager: LocationManaging
    private let walkingETAService: WalkingETAServiceProtocol
    private let orService = ORService()
    private let departureDelayKey = "departure_delay_minutes"
    private let departureCacheKey: String
    private let cacheMaxAge: TimeInterval = 90

    private var walkingRefreshTask: Task<Void, Never>?
    private var lastWalkLocation: CLLocation?
    private var pendingLocationRetries: Int = 0
    private let maxLocationRetries = 3
    private let freshLocationAccuracyThreshold: CLLocationAccuracy = 100
    private let freshLocationMaxAge: TimeInterval = 10

    enum WalkTimeSource: String {
        case auto
        case estimated
        case atStation

        var displayName: String {
            switch self {
            case .auto:
                return L10n.tr("departures.walking.source.auto")
            case .estimated:
                return L10n.tr("departures.walking.source.estimated")
            case .atStation:
                return L10n.tr("departures.walking.source.atStation")
            }
        }
    }

    enum WalkPreset: Equatable {
        case alreadyInStation
        case onTheWay
    }

    enum WalkingETAState: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    /// Visual style for the direction chip on departure cards.
    /// Same line, different directions get filled vs stroked.
    enum DirectionChipStyle: Equatable {
        case filled
        case stroked
    }

    init(
        stationId: String,
        apiService: APIServiceProtocol? = nil,
        locationManager: LocationManaging? = nil,
        walkingETAService: WalkingETAServiceProtocol? = nil
    ) {
        self.stationId = stationId
        self.apiService = apiService ?? RejseplanenAPIService()
        self.locationManager = locationManager ?? LocationManager()
        self.walkingETAService = walkingETAService ?? WalkingETAService(apiService: self.apiService)
        self.departureCacheKey = "departure_cache_\(stationId)"

        if let saved = UserDefaults.standard.object(forKey: departureDelayKey) as? Int {
            departureDelayMinutes = min(max(saved, 0), 20)
        }
        logWalkETA("state=initial value=nil source=nil isPlaceholder=true")
    }

    deinit {
        onTheWayCancellable?.cancel()
        walkingRefreshTask?.cancel()
    }

    // MARK: - Fetch

    func fetchDepartures() async {
        toastMessage = nil
        state = .loading

        do {
            pendingLocationRetries = 0
            if !isAtStationOverride {
                await refreshAutomaticWalkingEstimate(force: true)
            }

            let result = try await apiService.fetchDepartures(for: stationId)
            let normalized = Array(
                Dictionary(
                    result.map { (($0.journeyRef ?? $0.id), $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values
            )
            .sorted { lhs, rhs in
                (lhs.minutesUntilDepartureRaw ?? .max) < (rhs.minutesUntilDepartureRaw ?? .max)
            }

            departures = normalized
                .map { orService.enrich($0) }
                .map { enrichDecisionForCurrentState($0) }
            AppCacheStore.save(departures, key: departureCacheKey)
            isDataStale = false
            state = departures.isEmpty ? .empty : .success
        } catch {
            let message = AppErrorPresenter.message(for: error, context: .departures)
            if departures.isEmpty {
                if let cached = AppCacheStore.load([Departure].self, key: departureCacheKey, maxAge: cacheMaxAge) {
                    departures = cached.value
                        .map { orService.enrich($0) }
                        .map { enrichDecisionForCurrentState($0) }
                    isDataStale = true
                    state = departures.isEmpty ? .empty : .success
                    toastMessage = L10n.tr("departures.cache.toast")
                } else {
                    state = .error(message)
                }
            } else {
                state = .success
                isDataStale = true
                toastMessage = message
            }
        }
    }

    // MARK: - Departure delay (user input)

    func updateDepartureDelay(_ minutes: Int) {
        departureDelayMinutes = min(max(minutes, 0), 20)
        activePreset = nil
        isAtStationOverride = false
        UserDefaults.standard.set(departureDelayMinutes, forKey: departureDelayKey)
        recomputeCatchDecisions()
    }

    // MARK: - Presets

    func applyAlreadyInStationPreset() {
        stopOnTheWayUpdates()
        activePreset = .alreadyInStation
        isAtStationOverride = true
        walkTimeSource = .atStation
        walkMinutes = 1
        walkP10Minutes = 0
        walkP90Minutes = 2
        walkingETAState = .ready
        departureDelayMinutes = 0
        recomputeCatchDecisions()
    }

    func applyOnTheWayPreset() {
        activePreset = .onTheWay
        isAtStationOverride = false
        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        if auth == .denied || auth == .restricted {
            walkTimeSource = .estimated
            walkingETAState = .failed
            toastMessage = L10n.tr("departures.walking.locationUnavailable")
            recomputeCatchDecisions()
            return
        }

        startOnTheWayUpdates()
        Task { [weak self] in
            guard let self else { return }
            await self.refreshAutomaticWalkingEstimate(force: true)
            self.recomputeCatchDecisions()
        }
    }

    func stopOnTheWayUpdates() {
        onTheWayCancellable?.cancel()
        onTheWayCancellable = nil
        walkingRefreshTask?.cancel()
    }

    // MARK: - Recompute

    func recomputeCatchDecisions() {
        departures = departures.map { enrichDecisionForCurrentState($0) }
    }

    // MARK: - Display helpers

    func timeDisplay(for departure: Departure) -> (String, Bool) {
        if let rt = departure.rtTime {
            return (rt, rt != departure.time)
        }
        return (departure.time, false)
    }

    var errorMessage: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    var walkingTimeDisplayText: String {
        if walkingETAState == .idle || walkingETAState == .loading {
            return L10n.tr("departures.walking.calculating")
        }

        let center = Int(walkMinutes.rounded())
        let lower = Int(floor(min(walkP10Minutes, walkP90Minutes)))
        let upper = Int(ceil(max(walkP10Minutes, walkP90Minutes)))

        switch walkTimeSource {
        case .auto:
            if lower != upper {
                return L10n.tr("departures.walking.minutes.auto.interval", center, lower, upper)
            }
            return L10n.tr("departures.walking.minutes.auto.single", center)
        case .estimated:
            return L10n.tr("departures.walking.minutes.estimated", center)
        case .atStation:
            return L10n.tr("departures.walking.minutes.auto.single", center)
        }
    }

    var departureDelayDisplayText: String {
        if departureDelayMinutes == 0 {
            return L10n.tr("departures.walking.delay.preset.0")
        }
        return L10n.tr("departures.walking.delay.minutes", departureDelayMinutes)
    }

    var walkingUpdateStatusText: String? {
        if walkingETAState == .loading {
            return L10n.tr("departures.walking.waitingGPS")
        }
        if activePreset == .onTheWay {
            return L10n.tr("departures.walking.mode.live")
        }
        return nil
    }

    func catchProbabilityDisplay(for departure: Departure) -> String {
        DecisionPolicy.formatProbability(departure.catchProbability)
    }

    // MARK: - Direction chip

    /// Stable A/B assignment for same-line directions.
    /// First direction (alphabetically) = .filled, second = .stroked.
    func directionChipStyle(for departure: Departure) -> DirectionChipStyle {
        let lineKey = departure.name
        let directions = Set(departures.filter { $0.name == lineKey }.map(\.direction))
            .sorted()
        guard let index = directions.firstIndex(of: departure.direction) else { return .filled }
        return index == 0 ? .filled : .stroked
    }

    func directionText(for departure: Departure) -> String {
        "→ \(departure.direction)"
    }

    // MARK: - Private: walking ETA

    private var onTheWayCancellable: AnyCancellable?

    private func startOnTheWayUpdates() {
        onTheWayCancellable?.cancel()
        onTheWayCancellable = locationManager.currentLocationPublisher
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self else { return }
                Task { await self.scheduleWalkRefresh(for: location, force: false) }
            }
    }

    private func scheduleWalkRefresh(for location: CLLocation, force: Bool) async {
        if !force, let last = lastWalkLocation, location.distance(from: last) < 50 {
            return
        }

        walkingRefreshTask?.cancel()
        walkingRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self.refreshAutomaticWalkingEstimate(force: force)
            self.recomputeCatchDecisions()
        }
    }

    private func refreshAutomaticWalkingEstimate(force: Bool) async {
        walkingETAState = .loading
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
        }
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        let isAuthorized = auth == .authorizedWhenInUse || auth == .authorizedAlways

        guard isAuthorized else {
            logWalkETA("state=loading value=nil source=nil isPlaceholder=true reason=unauthorized")
            applyEstimatedFallbackWalkingEstimate()
            return
        }

        guard let currentLocation = locationManager.currentLocation else {
            logWalkETA("state=loading value=nil source=nil isPlaceholder=true reason=noLocation")
            await scheduleLocationRetryIfNeeded()
            return
        }

        guard isFreshLocation(currentLocation) else {
            logWalkETA("state=loading value=nil source=nil isPlaceholder=true reason=staleLocation acc=\(Int(currentLocation.horizontalAccuracy))")
            await scheduleLocationRetryIfNeeded()
            return
        }

        if !force, let last = lastWalkLocation, currentLocation.distance(from: last) < 50 {
            return
        }

        do {
            let age = Int(Date().timeIntervalSince(currentLocation.timestamp))
            logWalkETA("origin=(\(currentLocation.coordinate.latitude),\(currentLocation.coordinate.longitude), acc=\(Int(currentLocation.horizontalAccuracy)), ageS=\(age))")
            logWalkETA("dest=\(stationId) entranceId=\(stationId) parentId=unknown")
            let eta = try await walkingETAService.fetchWalkETA(
                origin: currentLocation.coordinate,
                destStopId: stationId
            )
            applyWalkETA(eta, from: currentLocation)
            lastWalkLocation = currentLocation
            pendingLocationRetries = 0
        } catch {
            logWalkETA("state=failed value=nil source=nil isPlaceholder=false reason=fetchError")
            applyEstimatedFallbackWalkingEstimate()
        }
    }

    private func applyWalkETA(_ walkETA: WalkETA, from location: CLLocation) {
        walkMinutes = Double(max(walkETA.minutes, 1))

        switch walkETA.source {
        case .hafasWalk:
            let accuracy = max(location.horizontalAccuracy, 10)
            let buffer = max(1, min(5, Int(ceil(accuracy / 70.0))))
            walkP10Minutes = max(walkMinutes - Double(buffer), 0)
            walkP90Minutes = walkMinutes + Double(buffer)
            walkTimeSource = .auto
        case .estimatedFallback:
            walkP10Minutes = max(walkMinutes - 2.0, 1.0)
            walkP90Minutes = walkMinutes + 3.0
            walkTimeSource = .estimated
        }
        walkingETAState = .ready
        logWalkETA("state=ready value=\(Int(walkMinutes.rounded())) source=\(walkETA.source) isPlaceholder=false")
    }

    private func applyEstimatedFallbackWalkingEstimate() {
        walkMinutes = 5.0
        walkP10Minutes = 3.0
        walkP90Minutes = 9.0
        walkTimeSource = .estimated
        walkingETAState = .ready
        logWalkETA("state=ready value=5 source=estimatedFallback isPlaceholder=false")
    }

    private func scheduleLocationRetryIfNeeded() async {
        guard pendingLocationRetries < maxLocationRetries else {
            applyEstimatedFallbackWalkingEstimate()
            return
        }
        pendingLocationRetries += 1
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await refreshAutomaticWalkingEstimate(force: false)
    }

    private func isFreshLocation(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy > 0
            && location.horizontalAccuracy <= freshLocationAccuracyThreshold
            && age <= freshLocationMaxAge
    }

    private func logWalkETA(_ message: String) {
        #if DEBUG
        fputs("[WalkETA] \(message) stationId=\(stationId)\n", stderr)
        #endif
    }

    // MARK: - Private: decision enrichment

    private func enrichDecisionForCurrentState(_ departure: Departure) -> Departure {
        DecisionPolicy.enrichDecision(
            departure: departure,
            departureDelayMinutes: departureDelayMinutes,
            walkMinutes: walkMinutes,
            walkP10: walkP10Minutes,
            walkP90: walkP90Minutes
        )
    }
}
