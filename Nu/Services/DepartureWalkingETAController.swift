import Foundation
import Combine
import CoreLocation

/// Coordinates walking-ETA state for the departure board feature.
///
/// Design goals:
/// - Deterministic state transitions for denied / unavailable location cases.
/// - Deterministic destination selection when no departure-derived mode exists yet.
/// - Keep all walking-ETA orchestration out of `DepartureBoardViewModel`.
///
/// Notes:
/// - This controller is UI-agnostic; the screen binds to `snapshot`.
/// - When there are no departures yet, the controller prefers the recommended
///   walking destination (if any) instead of falling back to `.unknown`.
@MainActor
final class DepartureWalkingETAController: ObservableObject {
    enum TimeSource: String, Equatable {
        case auto
        case estimated
        case atStation
    }

    enum Preset: Equatable {
        case alreadyInStation
        case onTheWay
    }

    enum Status: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    struct Snapshot: Equatable {
        var status: Status = .idle
        var walkMinutes: Double = 0
        var walkBaseMinutes: Double?
        var timeSource: TimeSource = .estimated
        var walkP10Minutes: Double = 3
        var walkP90Minutes: Double = 9
        var activeWalkMode: WalkingETADestination.Mode = .unknown
        var activePreset: Preset?
        var isAtStationOverride: Bool = false
        var toastMessage: String?
    }

    @Published private(set) var snapshot = Snapshot()

    private let stationId: String
    private let walkingDestinations: [WalkingETADestination]
    private let locationManager: LocationManaging
    private let walkingETAService: WalkingETAServiceProtocol

    private var trackedDepartures: [Departure] = []
    private var onTheWayCancellable: AnyCancellable?
    private var walkingRefreshTask: Task<Void, Never>?

    private var lastWalkLocation: CLLocation?
    private var pendingLocationRetries = 0

    private let maxLocationRetries = 10
    private let freshLocationAccuracyThreshold: CLLocationAccuracy = 200
    private let freshLocationMaxAge: TimeInterval = 120
    private let usableLocationAccuracyThreshold: CLLocationAccuracy = 1000
    private let usableLocationMaxAge: TimeInterval = 900
    private let locatingTimeout: TimeInterval = 20

    private var locatingStartedAt: Date?

    init(
        stationId: String,
        walkingDestinations: [WalkingETADestination],
        locationManager: LocationManaging,
        walkingETAService: WalkingETAServiceProtocol
    ) {
        self.stationId = stationId
        self.walkingDestinations = walkingDestinations
        self.locationManager = locationManager
        self.walkingETAService = walkingETAService
        snapshot.activeWalkMode = preferredWalkMode(from: [])
        logWalkETA("state=initial value=nil source=nil isPlaceholder=true")
    }

    deinit {
        onTheWayCancellable?.cancel()
        walkingRefreshTask?.cancel()
    }

    func updateDepartures(_ departures: [Departure]) {
        trackedDepartures = departures
        snapshot.activeWalkMode = preferredWalkMode(from: departures)
    }

    func clearToastMessage() {
        snapshot.toastMessage = nil
    }

    func stopOnTheWayUpdates() {
        onTheWayCancellable?.cancel()
        onTheWayCancellable = nil
        walkingRefreshTask?.cancel()
        walkingRefreshTask = nil
    }

    @discardableResult
    func applyAlreadyInStationPreset() -> Snapshot {
        stopOnTheWayUpdates()
        snapshot.activePreset = .alreadyInStation
        snapshot.isAtStationOverride = true
        snapshot.timeSource = .atStation
        snapshot.walkMinutes = 1
        snapshot.walkBaseMinutes = 1
        snapshot.walkP10Minutes = 0
        snapshot.walkP90Minutes = 2
        snapshot.status = .ready
        snapshot.toastMessage = nil
        snapshot.activeWalkMode = preferredWalkMode(from: trackedDepartures)
        return snapshot
    }

    @discardableResult
    func applyOnTheWayPreset() -> Snapshot {
        snapshot.activePreset = .onTheWay
        snapshot.isAtStationOverride = false
        snapshot.toastMessage = nil

        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        if auth == .denied || auth == .restricted {
            applyDeniedWalkingEstimate()
            snapshot.toastMessage = L10n.tr("departures.walking.locationUnavailable")
            return snapshot
        }

        startOnTheWayUpdates()

        walkingRefreshTask?.cancel()
        walkingRefreshTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshAutomaticWalkingEstimate(force: true)
        }

        return snapshot
    }

    @discardableResult
    func refreshAutomaticWalkingEstimate(force: Bool) async -> Snapshot {
        if force || locatingStartedAt == nil {
            locatingStartedAt = Date()
        }

        snapshot.status = .loading
        snapshot.toastMessage = nil
        snapshot.activeWalkMode = preferredWalkMode(from: trackedDepartures)

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
        }
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        let isAuthorized = auth == .authorizedWhenInUse || auth == .authorizedAlways

        guard isAuthorized else {
            logWalkETA("failure reason=unauthorized")
            applyDeniedWalkingEstimate()
            return snapshot
        }

        guard let currentLocation = locationManager.currentLocation else {
            logWalkETA("failure reason=noLocation")
            await scheduleLocationRetryIfNeeded()
            return snapshot
        }

        guard isUsableLocation(currentLocation) else {
            let age = Int(Date().timeIntervalSince(currentLocation.timestamp))
            logWalkETA("failure reason=badLocation acc=\(Int(currentLocation.horizontalAccuracy)) ageS=\(age)")
            await scheduleLocationRetryIfNeeded()
            return snapshot
        }

        if !isFreshLocation(currentLocation) {
            let age = Int(Date().timeIntervalSince(currentLocation.timestamp))
            logWalkETA("state=usingStaleLocation acc=\(Int(currentLocation.horizontalAccuracy)) ageS=\(age)")
        }

        if !force, let last = lastWalkLocation, currentLocation.distance(from: last) < 50 {
            return snapshot
        }

        do {
            let age = Int(Date().timeIntervalSince(currentLocation.timestamp))
            let selectedMode = preferredWalkMode(from: trackedDepartures)
            let destination = resolveWalkingStopPoint(for: currentLocation, mode: selectedMode)

            let destCoordText: String
            if let destinationCoord = destination.coordinate {
                destCoordText = "(\(destinationCoord.latitude),\(destinationCoord.longitude))"
            } else {
                destCoordText = "nil"
            }

            logWalkETA("origin=(\(currentLocation.coordinate.latitude),\(currentLocation.coordinate.longitude), acc=\(Int(currentLocation.horizontalAccuracy)), ageS=\(age))")
            logWalkETA("chosenMode=\(selectedMode.rawValue) chosenStopPointId=\(destination.stopId) name=\(destination.name ?? "nil") groupId=\(destination.groupId ?? "nil") stopPointCoord=\(destCoordText)")

            let eta = try await walkingETAService.fetchWalkETA(
                origin: currentLocation.coordinate,
                destination: destination,
                locationAccuracy: currentLocation.horizontalAccuracy,
                locationAgeSeconds: Date().timeIntervalSince(currentLocation.timestamp)
            )

            applyWalkETA(eta, from: currentLocation)
            lastWalkLocation = currentLocation
            pendingLocationRetries = 0
            locatingStartedAt = nil
            return snapshot
        } catch {
            logWalkETA("failure reason=requestError detail=\(error.localizedDescription)")
            await scheduleLocationRetryIfNeeded()
            return snapshot
        }
    }

    // MARK: - Private

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
            _ = await self.refreshAutomaticWalkingEstimate(force: force)
        }
    }

    private func applyWalkETA(_ walkETA: WalkETA, from location: CLLocation) {
        snapshot.walkMinutes = Double(max(walkETA.minutes, 1))
        snapshot.walkBaseMinutes = walkETA.baseMinutes.map { Double(max($0, 1)) }
        snapshot.toastMessage = nil

        switch walkETA.source {
        case .hafasWalk:
            let accuracy = max(location.horizontalAccuracy, 10)
            let buffer = max(1, min(5, Int(ceil(accuracy / 70.0))))
            snapshot.walkP10Minutes = max(snapshot.walkMinutes - Double(buffer), 0)
            snapshot.walkP90Minutes = snapshot.walkMinutes + Double(buffer)
            snapshot.timeSource = .auto

        case .estimatedFallback:
            snapshot.walkP10Minutes = max(snapshot.walkMinutes - 2.0, 1.0)
            snapshot.walkP90Minutes = snapshot.walkMinutes + 3.0
            snapshot.timeSource = .estimated
        }

        snapshot.status = .ready
        snapshot.activeWalkMode = preferredWalkMode(from: trackedDepartures)
        locatingStartedAt = nil

        logWalkETA("state=ready value=\(Int(snapshot.walkMinutes.rounded())) source=\(walkETA.source) isPlaceholder=false")
    }

    private func applyDeniedWalkingEstimate() {
        snapshot.status = .failed
        snapshot.walkMinutes = 0
        snapshot.walkBaseMinutes = nil
        snapshot.timeSource = .estimated
        snapshot.walkP10Minutes = 3
        snapshot.walkP90Minutes = 9
        locatingStartedAt = nil
        logWalkETA("state=failed value=nil source=nil isPlaceholder=false reason=unauthorized")
    }

    private func applyUnavailableWalkingEstimate() {
        snapshot.status = .failed
        snapshot.walkMinutes = 0
        snapshot.walkBaseMinutes = nil
        snapshot.timeSource = .estimated
        locatingStartedAt = nil
        logWalkETA("state=failed value=nil source=nil isPlaceholder=false reason=noETA")
    }

    private func scheduleLocationRetryIfNeeded() async {
        let elapsed = Date().timeIntervalSince(locatingStartedAt ?? Date())
        guard elapsed < locatingTimeout, pendingLocationRetries < maxLocationRetries else {
            applyUnavailableWalkingEstimate()
            return
        }

        pendingLocationRetries += 1
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        _ = await refreshAutomaticWalkingEstimate(force: false)
    }

    private func isFreshLocation(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy > 0
            && location.horizontalAccuracy <= freshLocationAccuracyThreshold
            && age <= freshLocationMaxAge
    }

    private func isUsableLocation(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy > 0
            && location.horizontalAccuracy <= usableLocationAccuracyThreshold
            && age <= usableLocationMaxAge
    }

    private func resolveWalkingStopPoint(
        for location: CLLocation,
        mode: WalkingETADestination.Mode
    ) -> WalkingETADestination {
        let fallback = WalkingETADestination(
            stopId: stationId,
            name: nil,
            groupId: nil,
            latitude: nil,
            longitude: nil,
            mode: .unknown,
            isRecommended: false
        )

        guard !walkingDestinations.isEmpty else { return fallback }

        let recommendedWithCoord = walkingDestinations.filter { $0.isRecommended && $0.coordinate != nil }
        let modeMatched = walkingDestinations.filter { $0.mode == mode && $0.coordinate != nil }
        let allWithCoord = walkingDestinations.filter { $0.coordinate != nil }

        let candidates: [WalkingETADestination]
        if mode != .unknown, !modeMatched.isEmpty {
            candidates = modeMatched
        } else if !recommendedWithCoord.isEmpty {
            candidates = recommendedWithCoord
        } else if !allWithCoord.isEmpty {
            candidates = allWithCoord
        } else {
            candidates = walkingDestinations
        }

        let selected = candidates.min { lhs, rhs in
            let lhsDistance = distance(from: location, to: lhs)
            let rhsDistance = distance(from: location, to: rhs)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.isRecommended != rhs.isRecommended {
                return lhs.isRecommended && !rhs.isRecommended
            }
            return lhs.stopId < rhs.stopId
        } ?? walkingDestinations.first ?? fallback

        snapshot.activeWalkMode = selected.mode
        return selected
    }

    private func distance(from location: CLLocation, to destination: WalkingETADestination) -> CLLocationDistance {
        guard let lat = destination.latitude, let lon = destination.longitude else {
            return .greatestFiniteMagnitude
        }
        return CLLocation(latitude: lat, longitude: lon).distance(from: location)
    }

    private func preferredWalkMode(from departures: [Departure]) -> WalkingETADestination.Mode {
        guard let first = departures.sorted(by: {
            ($0.minutesUntilDepartureRaw ?? .max) < ($1.minutesUntilDepartureRaw ?? .max)
        }).first else {
            if let recommended = walkingDestinations.first(where: { $0.isRecommended && $0.mode != .unknown }) {
                return recommended.mode
            }
            if let firstKnown = walkingDestinations.first(where: { $0.mode != .unknown }) {
                return firstKnown.mode
            }
            return .unknown
        }

        let text = first.type.uppercased()
        if text.contains("METRO") { return .metro }
        if text.contains("TOG") || text.contains("TRAIN") || text.contains("RAIL") { return .tog }
        if text.contains("BUS") { return .bus }
        return .unknown
    }

    private func logWalkETA(_ message: String) {
        #if DEBUG
        fputs("[WalkETA] \(message) stationId=\(stationId)\n", stderr)
        #endif
    }
}
