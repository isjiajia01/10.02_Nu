import Foundation
import Combine
import CoreLocation

/// 发车板页面 ViewModel。
///
/// 职责：
/// - 拉取并维护指定站点的发车列表。
/// - 暴露加载/错误状态给 SwiftUI 视图。
/// - 提供时间展示辅助逻辑（计划/实时）。
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
    @Published var simulatedWalkingTime: Double = 5.0
    @Published private(set) var walkTimeSource: WalkTimeSource = .fallback
    @Published private(set) var walkP10Minutes: Double = 3
    @Published private(set) var walkP90Minutes: Double = 9
    @Published private(set) var activePreset: WalkPreset?

    private let apiService: APIServiceProtocol
    private let stationId: String
    private let locationManager: LocationManaging
    private let orService = ORService()
    private let manualWalkMinutesKey = "manual_walking_minutes"
    private let departureCacheKey: String

    enum WalkTimeSource: String {
        case auto
        case pace
        case manual
        case preset
        case fallback

        var displayName: String {
            switch self {
            case .auto:
                return L10n.tr("departures.walking.source.auto")
            case .pace:
                return L10n.tr("departures.walking.source.pace")
            case .manual:
                return L10n.tr("departures.walking.source.manual")
            case .preset:
                return L10n.tr("departures.walking.source.preset")
            case .fallback:
                return L10n.tr("departures.walking.source.fallback")
            }
        }
    }

    enum WalkPreset: Equatable {
        case alreadyInStation
        case onTheWay
    }

    /// - Parameters:
    ///   - stationId: 需要查询的站点 ID。
    ///   - apiService: 默认使用 Rejseplanen 真实服务。
    init(
        stationId: String,
        apiService: APIServiceProtocol? = nil,
        locationManager: LocationManaging? = nil
    ) {
        self.stationId = stationId
        self.apiService = apiService ?? RejseplanenAPIService()
        self.locationManager = locationManager ?? LocationManager()
        self.departureCacheKey = "departure_cache_\(stationId)"

        if let saved = UserDefaults.standard.object(forKey: manualWalkMinutesKey) as? Double {
            simulatedWalkingTime = min(max(saved, 1), 20)
            walkTimeSource = .manual
            walkP10Minutes = max(simulatedWalkingTime - 2, 1)
            walkP90Minutes = simulatedWalkingTime + 4
        }
    }

    /// 拉取发车信息。
    func fetchDepartures() async {
        toastMessage = nil
        state = .loading

        do {
            if walkTimeSource != .manual {
                await refreshAutomaticWalkingEstimate()
            }

            let result = try await apiService.fetchDepartures(for: stationId)
            // 去重并按最近发车排序，再进入 OR 逻辑层。
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
                .map { orService.enrichDecision(departure: $0, walkingMinutes: simulatedWalkingTime) }
            AppCacheStore.save(departures, key: departureCacheKey)
            isDataStale = false
            state = departures.isEmpty ? .empty : .success
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? L10n.tr("departures.fetchFailed")
            if departures.isEmpty {
                if let cached = AppCacheStore.load([Departure].self, key: departureCacheKey) {
                    departures = cached.value
                        .map { orService.enrich($0) }
                        .map { orService.enrichDecision(departure: $0, walkingMinutes: simulatedWalkingTime) }
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

    /// 更新模拟步行时间并实时重算赶车决策（不重复请求网络）。
    func updateSimulatedWalkingTime(_ minutes: Double) {
        stopOnTheWayUpdates()
        simulatedWalkingTime = min(max(minutes, 1), 20)
        walkTimeSource = .manual
        activePreset = nil
        walkP10Minutes = max(simulatedWalkingTime - 2, 1)
        walkP90Minutes = simulatedWalkingTime + 4
        UserDefaults.standard.set(simulatedWalkingTime, forKey: manualWalkMinutesKey)
        recomputeCatchDecisions()
    }

    func applyAlreadyInStationPreset() {
        stopOnTheWayUpdates()
        activePreset = .alreadyInStation
        walkTimeSource = .preset
        simulatedWalkingTime = 2
        walkP10Minutes = 1
        walkP90Minutes = 4
        recomputeCatchDecisions()
    }

    func applyOnTheWayPreset() {
        activePreset = .onTheWay
        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        if auth == .denied || auth == .restricted {
            toastMessage = L10n.tr("departures.walking.locationUnavailable")
            applyFallbackWalkingEstimate()
            recomputeCatchDecisions()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshAutomaticWalkingEstimate()
            self.recomputeCatchDecisions()
        }
    }

    func stopOnTheWayUpdates() {
        // 保留接口，当前版本已取消 15 秒轮询更新。
    }

    /// 仅重算 `catchStatus / catchProbability`，保留当前列表顺序和其它字段。
    func recomputeCatchDecisions() {
        departures = departures.map {
            orService.enrichDecision(departure: $0, walkingMinutes: simulatedWalkingTime)
        }
    }

    /// 时间展示逻辑。
    ///
    /// 返回值：
    /// - `String`: 优先显示实时时间，否则显示计划时间。
    /// - `Bool`: 是否需要用“延误”样式强调。
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

    var walkingTimeIntervalText: String {
        let lower = Int(floor(walkP10Minutes))
        let upper = Int(ceil(walkP90Minutes))
        return "\(lower)-\(upper)"
    }

    var walkingUpdateStatusText: String? {
        return nil
    }

    func catchProbabilityDisplay(for departure: Departure) -> String {
        if departure.rtTime == nil {
            return L10n.tr("departures.catch.conservative")
        }
        guard let probability = departure.catchProbability else {
            return L10n.tr("departures.catch.insufficient")
        }
        let clamped = min(max(probability, 0), 1)
        if clamped < 0.05 {
            return L10n.tr("departures.catch.lt5")
        }
        return L10n.tr("departures.catch.percent", Int((clamped * 100).rounded()))
    }

    private func refreshAutomaticWalkingEstimate() async {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAuthorization()
        }
        locationManager.startUpdatingLocation()

        let auth = locationManager.authorizationStatus
        let isAuthorized = auth == .authorizedWhenInUse || auth == .authorizedAlways

        guard isAuthorized, let currentLocation = locationManager.currentLocation else {
            applyFallbackWalkingEstimate()
            return
        }

        do {
            let nearby = try await apiService.fetchNearbyStops(
                coordX: currentLocation.coordinate.longitude,
                coordY: currentLocation.coordinate.latitude
            )

            if let station = nearby.first(where: { $0.id == stationId }),
               let distance = station.distanceMeters {
                // 以 normal 步速 1.25m/s 估计，并加入进站摩擦 1 分钟。
                let baselineMinutes = max((distance / 75.0) + 1.0, 1.0)
                simulatedWalkingTime = baselineMinutes
                walkP10Minutes = max(baselineMinutes - 2.0, 1.0)
                walkP90Minutes = baselineMinutes + 2.0
                walkTimeSource = .auto
                return
            }
        } catch {
            // 降级到 fallback，不影响发车主流程。
        }

        applyFallbackWalkingEstimate()
    }

    private func applyFallbackWalkingEstimate() {
        simulatedWalkingTime = 5.0
        walkP10Minutes = 3.0
        walkP90Minutes = 9.0
        walkTimeSource = .fallback
    }
}
