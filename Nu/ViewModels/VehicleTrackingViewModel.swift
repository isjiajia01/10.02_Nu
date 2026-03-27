import Foundation
import SwiftUI
import Combine
import MapKit

@MainActor
final class VehicleTrackingViewModel: ObservableObject {
    struct TrackingDebugInfo: Equatable {
        static let empty = TrackingDebugInfo()
    }

    enum MotionState: Equatable {
        case moving
        case stopped
        case stale

        var label: String {
            switch self {
            case .moving: return "moving"
            case .stopped: return "likely stopped"
            case .stale: return "stale"
            }
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case tracking
        case empty
        case blocked(String)
        case failed(String)
    }

    // MARK: - Published state

    @Published private(set) var state: State = .idle
    @Published private(set) var trackedVehicle: JourneyVehicle?
    @Published private(set) var nearbyLineVehicles: [JourneyVehicle] = []
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var routeStops: [JourneyStop] = []
    @Published private(set) var motionState: MotionState = .stale
    @Published private(set) var lastUpdateDate: Date?
    @Published private(set) var mapCenterCoordinate: CLLocationCoordinate2D?
    /// P0-2: incremented only when valid (generation-checked) data is published.
    @Published private(set) var displayGeneration: Int = 0
    @Published var visibleRegion: MKCoordinateRegion
    @Published var statusText: String = ""

    /// Not @Published – the Representable reads this when SwiftUI triggers
    /// an update, but changes to this flag alone must not trigger a redraw.
    private(set) var isInteracting = false

    // MARK: - Private state

    private let apiService: APIServiceProtocol
    private let departure: Departure
    private let operationDate: String?
    private let originStopName: String
    private let selectedStopCoordinate: CLLocationCoordinate2D?
    private var identity: TrackingIdentity
    private var pollingTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?
    private var interactionPauseTask: Task<Void, Never>?
    private var fetchQueueTask: Task<Void, Never>?
    private var scoringTask: Task<JourneyVehicle?, Never>?
    private var routeTask: Task<Void, Never>?
    private var isFetching = false
    private var pendingFetch = false
    private var fetchGeneration = 0
    private var stableMatchStreak = 0
    private var cooldownRounds = 0
    private var stagnationRounds = 0
    private var nearbyRenderRound = 0
    private var missedRounds = 0
    private var recentMainDeltas: [Double] = []
    private var previousMainCoordinate: CLLocationCoordinate2D?
    private var previousMainDate: Date?
    private var velocityLatPerSec: Double = 0
    private var velocityLonPerSec: Double = 0
    private var localRadiusMeters: Double = 800
    private var forceGlobalReacquireRounds = 0
    private let pollingInterval: TimeInterval = 7
    private let minimumFetchInterval: TimeInterval = 2.0
    private var lastFetchAt: Date = .distantPast
    private var hasCompletedBootstrapFetch = false

    // MARK: P0-5 perf counters
    #if DEBUG
    private var fetchTriggeredCount = 0
    private var fetchStartedCount = 0
    private var fetchDedupedCount = 0
    private var lastPerfReportDate = Date()
    #endif

    // MARK: - Init / deinit

    init(
        departure: Departure,
        operationDate: String?,
        apiService: APIServiceProtocol,
        initialRegion: MKCoordinateRegion
    ) {
        self.departure = departure
        self.operationDate = operationDate
        self.apiService = apiService
        self.originStopName = departure.stop
        self.selectedStopCoordinate = departure.passListStops.first(where: {
            VehicleTrackingMatcher.normalizedStopName($0.name) == VehicleTrackingMatcher.normalizedStopName(departure.stop)
        }).flatMap { stop in
            guard let lat = stop.lat, let lon = stop.lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        self.visibleRegion = initialRegion
        self.identity = TrackingIdentity(
            journeyRef: departure.journeyRef,
            jid: nil,
            line: departure.name,
            direction: departure.direction,
            plannedOrRealtimeDeparture: departure.effectiveDepartureDate?.date
        )
    }

    deinit {
        pollingTask?.cancel()
        identityTask?.cancel()
        interactionPauseTask?.cancel()
        fetchQueueTask?.cancel()
        scoringTask?.cancel()
        routeTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        guard pollingTask == nil else { return }
        state = .loading
        statusText = "Resolving vehicle data…"
        isInteracting = false
        loadRouteSkeletonOnce()
        identityTask?.cancel()
        identityTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrapIdentity()
            self.requestFetch(reason: "identity-resolved")
        }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            self.requestFetch(reason: "start")
            while !Task.isCancelled {
                if !self.isInteracting {
                    self.requestFetch(reason: "poll")
                }
                let interval: TimeInterval
                if ProcessInfo.processInfo.isLowPowerModeEnabled {
                    interval = 12
                } else if self.forceGlobalReacquireRounds > 0 {
                    interval = 5
                } else {
                    interval = self.pollingInterval
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        identityTask?.cancel()
        identityTask = nil
        interactionPauseTask?.cancel()
        fetchQueueTask?.cancel()
        fetchQueueTask = nil
        pendingFetch = false
        scoringTask?.cancel()
        scoringTask = nil
        routeTask?.cancel()
        routeTask = nil
    }

    func updateRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
    }

    func pauseForInteraction() {
        isInteracting = true
        interactionPauseTask?.cancel()
        interactionPauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isInteracting = false
            self.requestFetch(reason: "interaction-timeout")
        }
    }

    func resumeAfterInteraction() {
        interactionPauseTask?.cancel()
        interactionPauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isInteracting = false
            self.requestFetch(reason: "interaction-end")
        }
    }

    // MARK: - Identity bootstrap

    private func bootstrapIdentity() async {
        do {
            let resolved = try await withTimeout(seconds: 5) {
                try await self.apiService.resolveTrackingIdentity(from: self.departure, operationDate: self.operationDate)
            }
            identity = resolved
        } catch {
            identity.matchConfidence = .heuristic
        }
    }

    // MARK: - Route skeleton

    private func loadRouteSkeletonOnce() {
        guard routeCoordinates.isEmpty else { return }
        guard let ref = departure.journeyRef, !ref.isEmpty else { return }

        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await self.apiService.fetchJourneyDetail(id: ref, date: self.operationDate)
                let coords = detail.stops.compactMap { stop -> CLLocationCoordinate2D? in
                    guard let lat = stop.lat, let lon = stop.lon else { return nil }
                    guard abs(lat) <= 90, abs(lon) <= 180 else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                let sanitized = self.sanitizeRouteCoordinates(coords)
                if sanitized.count >= 2 {
                    self.routeCoordinates = sanitized
                }
                self.routeStops = detail.stops
            } catch {
                // Route highlight is best-effort and should not block tracking.
            }
        }
    }

    private func sanitizeRouteCoordinates(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }

        let regional = coords.filter {
            (53.5...58.5).contains($0.latitude) && (6.0...16.8).contains($0.longitude)
        }
        let base = regional.count >= 2 ? regional : coords

        var result: [CLLocationCoordinate2D] = []
        for point in base {
            guard let last = result.last else {
                result.append(point)
                continue
            }
            let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            if distance <= 80_000 {
                result.append(point)
            } else {
                #if DEBUG
                AppLogger.debug("[ROUTE] drop outlier point lat=\(point.latitude) lon=\(point.longitude) jump=\(Int(distance))m")
                #endif
            }
        }

        if result.count >= 2 {
            return result
        }
        return base
    }

    // MARK: - Fetch scheduling (P0-1: single channel + in-flight gate)

    private func requestFetch(reason: String) {
        #if DEBUG
        fetchTriggeredCount += 1
        #endif
        pendingFetch = true
        guard fetchQueueTask == nil else {
            #if DEBUG
            fetchDedupedCount += 1
            #endif
            return
        }
        fetchQueueTask = Task { [weak self] in
            guard let self else { return }
            await self.drainFetchQueue()
        }
    }

    private func drainFetchQueue() async {
        while !Task.isCancelled {
            guard pendingFetch else { break }
            pendingFetch = false
            fetchGeneration += 1
            let generation = fetchGeneration
            await fetchOnce(generation: generation)
        }
        fetchQueueTask = nil
        if pendingFetch, !Task.isCancelled {
            requestFetch(reason: "drain-restart")
        }
    }

    private func isGenerationCurrent(_ generation: Int) -> Bool {
        generation == fetchGeneration && !Task.isCancelled
    }

    // MARK: - Core fetch (P0-2: generation guards at all three checkpoints)

    private func fetchOnce(generation: Int) async {
        guard !isFetching else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFetchAt)
        if elapsed < minimumFetchInterval {
            let remaining = minimumFetchInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        guard isGenerationCurrent(generation) else { return }
        isFetching = true
        #if DEBUG
        fetchStartedCount += 1
        #endif
        defer {
            isFetching = false
            lastFetchAt = Date()
            #if DEBUG
            reportPerfIfNeeded()
            #endif
        }

        if state == .loading {
            statusText = "Searching vehicles in map area…"
        }
        let isBootstrap = !hasCompletedBootstrapFetch
        let routeSearchRequired = selectedVehicleLikelyNeedsRouteSearch
        let boxes = makeFetchBoxes(isBootstrap: isBootstrap, routeSearchRequired: routeSearchRequired)
        guard !boxes.isEmpty else { return }

        do {
            var allVehicles: [JourneyVehicle] = []
            for box in boxes {
                let filters = makeFilters()
                let items = try await withTimeout(seconds: hasCompletedBootstrapFetch ? 6 : 5) {
                    try await self.apiService.fetchJourneyPositions(
                        bbox: box,
                        filters: filters,
                        positionMode: .calcReport
                    )
                }
                // P0-2 checkpoint 1: generation check after network return
                guard isGenerationCurrent(generation) else { return }
                allVehicles.append(contentsOf: items)
            }
            guard isGenerationCurrent(generation) else { return }

            let deduped = Array(
                Dictionary(allVehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
            )
            guard !deduped.isEmpty else {
                if case .blocked = state {
                    return
                }
                missedRounds += 1
                if missedRounds >= 2 {
                    localRadiusMeters = min(localRadiusMeters * 1.5, visibleRadiusMeters())
                    forceGlobalReacquireRounds = min(2, forceGlobalReacquireRounds + 1)
                }
                state = .empty
                nearbyLineVehicles = []
                statusText = "No matching vehicle in current map area"
                motionState = .stale
                return
            }
            missedRounds = 0

            if trackedVehicle == nil {
                trackedVehicle = deduped[0]
            }
            if case .loading = state {
                state = .tracking
                statusText = "Possible match · refining target…"
            }

            let identitySnapshot = identity
            let predicted = predictedMainCoordinate(at: Date())
            let routeStopsSnapshot = routeStops
            scoringTask?.cancel()
            let currentTracked = trackedVehicle
            scoringTask = Task.detached(priority: .userInitiated) {
                VehicleTrackingMatcher.selectBestVehicle(
                    from: deduped,
                    context: .init(
                        identity: identitySnapshot,
                        currentMain: currentTracked,
                        predictedCoordinate: predicted,
                        originStopName: self.originStopName,
                        routeStops: routeStopsSnapshot,
                        selectedStopCoordinate: self.selectedStopCoordinate
                    )
                )
            }
            let selection = await scoringTask?.value
            let matched = selection ?? deduped[0]
            // P0-2 checkpoint 2: generation check after scoring
            guard isGenerationCurrent(generation) else { return }
            let previousMatchedId = identity.lastMatchedVehicleId ?? trackedVehicle?.id
            if previousMatchedId == matched.id {
                stableMatchStreak += 1
            } else {
                stableMatchStreak = 1
            }

            let threshold = stationaryThresholdMeters()
            let delta = trackedVehicle.map {
                CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                    .distance(from: CLLocation(latitude: matched.coordinate.latitude, longitude: matched.coordinate.longitude))
            } ?? 0
            if trackedVehicle?.id == matched.id, delta < threshold {
                stagnationRounds += 1
            } else {
                stagnationRounds = 0
            }
            if cooldownRounds > 0 {
                cooldownRounds -= 1
            }

            if stagnationRounds >= 3 && cooldownRounds == 0 {
                forceGlobalReacquireRounds = 2
                cooldownRounds = 2
            }

            // P0-2: increment display generation before publishing to UI
            displayGeneration += 1
            trackedVehicle = matched
            identity.lastKnownCoordinate = matched.coordinate
            identity.lastMatchedVehicleId = matched.id
            identity.lastMatchAt = Date()
            lastUpdateDate = Date()
            mapCenterCoordinate = matched.coordinate
            nearbyRenderRound += 1
            if nearbyRenderRound % 3 == 0 || nearbyLineVehicles.isEmpty {
                nearbyLineVehicles = buildNearbyLineVehicles(from: deduped, primary: matched)
            }
            if identity.jid != nil, matched.jid == identity.jid {
                identity.matchConfidence = .exact
            } else if identity.matchConfidence != .exact {
                identity.matchConfidence = .heuristic
            }
            state = .tracking
            let accuracy: String
            if identity.matchConfidence == .exact {
                accuracy = "Exact match"
            } else if stableMatchStreak >= 3 {
                accuracy = "Likely match"
            } else {
                accuracy = "Possible match"
            }
            let source: String
            if let reported = matched.isReportedPosition {
                source = reported ? "reported" : "estimated"
            } else {
                source = "calc/report (mode)"
            }
            let nearbyCount = nearbyLineVehicles.count
            statusText = nearbyCount > 0
                ? "\(accuracy) · \(source) · \(nearbyCount + 1) vehicles on line"
                : "\(accuracy) · \(source)"
            motionState = stagnationRounds >= 3 ? .stopped : .moving
            updateMainVelocity(with: matched.coordinate, at: Date())
            localRadiusMeters = 800
            if forceGlobalReacquireRounds > 0 {
                forceGlobalReacquireRounds -= 1
            }
            hasCompletedBootstrapFetch = true
            if !isInteracting {
                visibleRegion = Self.regionAroundVehicle(matched.coordinate)
            }
        } catch let api as APIError {
            switch api {
            case .unauthorized, .forbidden:
                state = .blocked(AppErrorPresenter.message(for: api, context: .journeyDetail))
                statusText = ""
                nearbyLineVehicles = []
                motionState = .stale
                stop()
            default:
                state = .failed(AppErrorPresenter.message(for: api, context: .journeyDetail))
                nearbyLineVehicles = []
                motionState = .stale
            }
        } catch is VehicleTrackingTimeoutError {
            state = .failed("Vehicle request timed out. Please try again.")
            nearbyLineVehicles = []
            motionState = .stale
        } catch {
            state = .failed(AppErrorPresenter.message(for: error, context: .journeyDetail))
            nearbyLineVehicles = []
            motionState = .stale
        }
    }

    private static func regionAroundVehicle(_ coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    }

    // MARK: - Filters & scoring

    private func makeFilters() -> JourneyPosFilters {
        var filters = JourneyPosFilters()
        filters.jid = identity.jid
        if let rawLine = identity.line, !rawLine.isEmpty {
            var values: [String] = [rawLine]
            if let token = normalizedLineToken(rawLine), token != rawLine {
                values.append(token)
            }
            filters.lines = Array(Set(values))
        }
        return filters
    }

    private func buildNearbyLineVehicles(from vehicles: [JourneyVehicle], primary: JourneyVehicle) -> [JourneyVehicle] {
        guard let target = normalizedLineToken(identity.line) ?? normalizedLineToken(primary.line) else {
            return []
        }

        let center = visibleRegion.center
        return vehicles
            .filter { $0.id != primary.id }
            .filter { normalizedLineToken($0.line) == target }
            .sorted { lhs, rhs in
                let l = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
                    .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                let r = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
                    .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                return l < r
            }
            .prefix(12)
            .map { $0 }
    }

    private func normalizedLineToken(_ text: String?) -> String? {
        VehicleTrackingMatcher.normalizedLineToken(text)
    }

    // MARK: - BBox strategy

    private func makeFetchBoxes(isBootstrap: Bool, routeSearchRequired: Bool) -> [JourneyPosBBox] {
        VehicleTrackingMatcher.makeFetchBoxes(
            for: .init(
                isBootstrap: isBootstrap,
                forceGlobalReacquireRounds: forceGlobalReacquireRounds,
                trackedVehicle: trackedVehicle,
                identity: identity,
                routeCoordinates: routeCoordinates,
                visibleRegion: visibleRegion,
                localRadiusMeters: localRadiusMeters,
                originStopName: originStopName
            )
        )
    }

    private var selectedVehicleLikelyNeedsRouteSearch: Bool {
        let normalizedStop = VehicleTrackingMatcher.normalizedStopName(originStopName)
        guard !normalizedStop.isEmpty else { return false }
        if let trackedVehicle,
           let stopName = trackedVehicle.stopName,
           VehicleTrackingMatcher.normalizedStopName(stopName) == normalizedStop {
            return false
        }
        return true
    }

    private func visibleRadiusMeters() -> Double {
        let center = CLLocation(latitude: visibleRegion.center.latitude, longitude: visibleRegion.center.longitude)
        let edge = CLLocation(
            latitude: visibleRegion.center.latitude + visibleRegion.span.latitudeDelta / 2.0,
            longitude: visibleRegion.center.longitude
        )
        return max(500, center.distance(from: edge))
    }

    // MARK: - Motion tracking

    private func stationaryThresholdMeters() -> Double {
        guard !recentMainDeltas.isEmpty else { return 20 }
        let sorted = recentMainDeltas.sorted()
        let median = sorted[sorted.count / 2]
        return max(20, 3 * median)
    }

    private func updateMainVelocity(with coordinate: CLLocationCoordinate2D, at date: Date) {
        if let prev = previousMainCoordinate, let prevDate = previousMainDate {
            let dt = max(1, date.timeIntervalSince(prevDate))
            velocityLatPerSec = (coordinate.latitude - prev.latitude) / dt
            velocityLonPerSec = (coordinate.longitude - prev.longitude) / dt
            let d = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            recentMainDeltas.append(d)
            if recentMainDeltas.count > 10 {
                recentMainDeltas.removeFirst(recentMainDeltas.count - 10)
            }
        }
        previousMainCoordinate = coordinate
        previousMainDate = date
    }

    private func predictedMainCoordinate(at now: Date) -> CLLocationCoordinate2D? {
        guard let base = identity.lastKnownCoordinate ?? trackedVehicle?.coordinate,
              let last = identity.lastMatchAt else { return nil }
        let dt = max(0, now.timeIntervalSince(last))
        return CLLocationCoordinate2D(
            latitude: base.latitude + velocityLatPerSec * dt,
            longitude: base.longitude + velocityLonPerSec * dt
        )
    }

    // MARK: - Timeout utility

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VehicleTrackingTimeoutError()
            }
            guard let first = try await group.next() else {
                throw VehicleTrackingTimeoutError()
            }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Debug perf reporting (P0-5)

    #if DEBUG
    private func reportPerfIfNeeded() {
        guard DebugFlags.trackingPerfLoggingEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPerfReportDate) >= 30 else { return }
        AppLogger.debug("[TrackingPerf] 30s: fetchTriggered=\(fetchTriggeredCount) fetchStarted=\(fetchStartedCount) fetchDeduped=\(fetchDedupedCount)")
        fetchTriggeredCount = 0
        fetchStartedCount = 0
        fetchDedupedCount = 0
        lastPerfReportDate = now
    }
    #endif
}

private struct VehicleTrackingTimeoutError: Error {}
