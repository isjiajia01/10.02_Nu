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
    @Published private(set) var walkMinutes: Double = 0.0
    @Published private(set) var walkBaseMinutes: Double?
    @Published private(set) var walkTimeSource: WalkTimeSource = .estimated
    @Published private(set) var walkP10Minutes: Double = 3
    @Published private(set) var walkP90Minutes: Double = 9
    @Published private(set) var activeWalkMode: WalkingETADestination.Mode = .unknown

    // Departure delay (user input: "I'll leave in N min")
    @Published var departureDelayMinutes: Int = 0

    // Presets
    @Published private(set) var activePreset: WalkPreset?
    @Published private(set) var isAtStationOverride: Bool = false

    private let departureLoader: DepartureBoardLoader
    private let delayStore: DepartureDelayStore
    private let walkingETAController: DepartureWalkingETAController

    private var walkingStateCancellable: AnyCancellable?

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
        walkingDestinations: [WalkingETADestination] = [],
        apiService: APIServiceProtocol? = nil,
        locationManager: LocationManaging? = nil,
        walkingETAService: WalkingETAServiceProtocol? = nil
    ) {
        let resolvedAPIService = apiService ?? RejseplanenAPIService()
        let resolvedLocationManager = locationManager ?? LocationManager()
        let resolvedWalkingETAService = walkingETAService ?? WalkingETAService(
            apiService: resolvedAPIService,
            overheadSeconds: AppConfig.walkETAOverheadSeconds
        )

        self.departureLoader = DepartureBoardLoader(
            stationId: stationId,
            apiService: resolvedAPIService
        )
        self.delayStore = DepartureDelayStore()
        self.walkingETAController = DepartureWalkingETAController(
            stationId: stationId,
            walkingDestinations: walkingDestinations,
            locationManager: resolvedLocationManager,
            walkingETAService: resolvedWalkingETAService
        )

        departureDelayMinutes = delayStore.load()
        bindWalkingController()
        applyWalkingSnapshot(walkingETAController.snapshot)
    }

    deinit {
        walkingStateCancellable?.cancel()
    }

    // MARK: - Fetch

    func fetchDepartures() async {
        toastMessage = nil
        state = .loading

        if !isAtStationOverride {
            _ = await walkingETAController.refreshAutomaticWalkingEstimate(force: true)
        }

        switch await departureLoader.load() {
        case .success(let loadedDepartures, let isDataStale, let loaderToastMessage):
            walkingETAController.updateDepartures(loadedDepartures)
            departures = loadedDepartures.map { enrichDecisionForCurrentState($0) }
            self.isDataStale = isDataStale
            state = departures.isEmpty ? .empty : .success
            toastMessage = loaderToastMessage

        case .failure(let message):
            if departures.isEmpty {
                state = .error(message)
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
        delayStore.save(departureDelayMinutes)
        recomputeCatchDecisions()
    }

    // MARK: - Presets

    func applyAlreadyInStationPreset() {
        _ = walkingETAController.applyAlreadyInStationPreset()
        departureDelayMinutes = 0
        recomputeCatchDecisions()
    }

    func applyOnTheWayPreset() {
        _ = walkingETAController.applyOnTheWayPreset()
        if walkingETAState == .failed {
            recomputeCatchDecisions()
        }
    }

    func stopOnTheWayUpdates() {
        walkingETAController.stopOnTheWayUpdates()
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
        if walkingETAState == .idle {
            return L10n.tr("departures.walking.calculating")
        }
        if walkingETAState == .loading {
            return L10n.tr("departures.walking.locating")
        }
        if walkingETAState == .failed {
            return L10n.tr("departures.walking.unavailable")
        }

        let center = Int(walkMinutes.rounded())
        let base = Int((walkBaseMinutes ?? walkMinutes).rounded())

        switch walkTimeSource {
        case .auto:
            if base != center {
                return "\(base)-\(center) min"
            }
            return "\(center) min"
        case .estimated:
            return L10n.tr("departures.walking.minutes.estimated", center)
        case .atStation:
            return L10n.tr("departures.walking.minutes.auto.single", center)
        }
    }

    var walkingTimeTitleText: String {
        "Walk:"
    }

    var walkingEstimateHintText: String? {
        guard walkingETAState == .ready else { return nil }
        return "Best-safe estimate"
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

    // MARK: - Private

    private func bindWalkingController() {
        walkingStateCancellable = walkingETAController.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.applyWalkingSnapshot(snapshot)
                if !self.departures.isEmpty {
                    self.recomputeCatchDecisions()
                }
            }
    }

    private func applyWalkingSnapshot(_ snapshot: DepartureWalkingETAController.Snapshot) {
        walkingETAState = mapStatus(snapshot.status)
        walkMinutes = snapshot.walkMinutes
        walkBaseMinutes = snapshot.walkBaseMinutes
        walkTimeSource = mapTimeSource(snapshot.timeSource)
        walkP10Minutes = snapshot.walkP10Minutes
        walkP90Minutes = snapshot.walkP90Minutes
        activeWalkMode = snapshot.activeWalkMode
        activePreset = mapPreset(snapshot.activePreset)
        isAtStationOverride = snapshot.isAtStationOverride

        if let toast = snapshot.toastMessage {
            toastMessage = toast
        }
    }

    private func mapStatus(_ status: DepartureWalkingETAController.Status) -> WalkingETAState {
        switch status {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .ready:
            return .ready
        case .failed:
            return .failed
        }
    }

    private func mapTimeSource(_ source: DepartureWalkingETAController.TimeSource) -> WalkTimeSource {
        switch source {
        case .auto:
            return .auto
        case .estimated:
            return .estimated
        case .atStation:
            return .atStation
        }
    }

    private func mapPreset(_ preset: DepartureWalkingETAController.Preset?) -> WalkPreset? {
        switch preset {
        case .alreadyInStation:
            return .alreadyInStation
        case .onTheWay:
            return .onTheWay
        case nil:
            return nil
        }
    }

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
