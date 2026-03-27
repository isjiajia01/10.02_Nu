import Foundation
import CoreLocation
import Combine

/// 附近站点页面的状态管理（MVVM）。
///
/// 职责：
/// - 监听定位并请求附近站点。
/// - 管理搜索关键字与防抖。
/// - 通过显式状态机驱动 UI（Loading / Success / Empty / Error）。
@MainActor
final class NearbyStationsViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case loading
        case success
        case empty
        case error(String)
    }

    @Published private(set) var stations: [StationModel] = []
    @Published private(set) var stationGroups: [StationGroupModel] = []
    @Published private(set) var filteredStationGroups: [StationGroupModel] = []
    @Published private(set) var state: ViewState = .idle
    @Published private(set) var isDataStale: Bool = false
    @Published var toastMessage: String?
    @Published var searchText: String = "" {
        didSet { scheduleDebouncedFilter() }
    }

    private let apiService: APIServiceProtocol
    private let locationManager: LocationManaging
    private var debounceTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false
    private let fallbackLongitude = 12.568337
    private let fallbackLatitude = 55.676098
    private let cacheKey = "nearby_stations_cache_v1"
    private let cacheMaxAge: TimeInterval = 180
    private let searchDebounceNanoseconds: UInt64 = 500_000_000
    private let bootstrapFallbackNanoseconds: UInt64 = 2_500_000_000

    init(apiService: APIServiceProtocol, locationManager: LocationManaging) {
        self.apiService = apiService
        self.locationManager = locationManager
    }

    deinit {
        debounceTask?.cancel()
        bootstrapTask?.cancel()
        cancellables.removeAll()
    }

    /// 视图首次加载入口。
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        state = .loading
        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()
        observeLocationChanges()
        scheduleBootstrapFallback()
    }

    /// 刷新入口：优先使用当前位置，否则等待下一次定位更新。
    func refreshNearbyStations() async {
        if let location = locationManager.currentLocation {
            await fetchNearbyStations(location: location)
            return
        }

        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            state = .error(L10n.tr("stations.locationDenied"))
        default:
            await fetchNearbyStations(coordX: fallbackLongitude, coordY: fallbackLatitude)
            if toastMessage == nil {
                toastMessage = L10n.tr("stations.locationPendingFallback")
            }
        }
    }

    /// 供视图绑定的错误消息。
    var errorMessage: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    private func observeLocationChanges() {
        cancellables.removeAll()

        locationManager.authorizationStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] auth in
                if auth == .denied || auth == .restricted {
                    self?.state = .error(L10n.tr("stations.locationDenied"))
                }
            }
            .store(in: &cancellables)

        locationManager.currentLocationPublisher
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self else { return }
                self.cancelBootstrapFallback()
                Task { await self.fetchNearbyStations(location: location) }
            }
            .store(in: &cancellables)
    }

    private func scheduleBootstrapFallback() {
        cancelBootstrapFallback()
        bootstrapTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: self.bootstrapFallbackNanoseconds)
            guard self.stations.isEmpty else { return }
            await self.fetchNearbyStations(coordX: self.fallbackLongitude, coordY: self.fallbackLatitude)
            if self.toastMessage == nil {
                self.toastMessage = L10n.tr("stations.locationPendingFallback")
            }
        }
    }

    private func cancelBootstrapFallback() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
    }

    /// 拉取附近站点。
    private func fetchNearbyStations(location: CLLocation) async {
        await fetchNearbyStations(
            coordX: location.coordinate.longitude,
            coordY: location.coordinate.latitude
        )
    }

    /// 用指定坐标拉取附近站点（用于定位成功或回退坐标）。
    private func fetchNearbyStations(coordX: Double, coordY: Double) async {
        toastMessage = nil
        state = .loading

        do {
            let result = try await apiService.fetchNearbyStops(
                coordX: coordX,
                coordY: coordY
            )

            let sorted = result.sorted {
                ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude)
            }
            stations = sorted
            stationGroups = StationGrouping.buildGroups(sorted)
            AppCacheStore.save(stations, key: cacheKey)
            isDataStale = false
            applyFilter()

            // 异步 enrich 缺少 products 的站点（不阻塞列表展示）
            await enrichStationsIfNeeded()
        } catch {
            let message = AppErrorPresenter.message(for: error, context: .stations)
            if stations.isEmpty {
                if let cached = AppCacheStore.load([StationModel].self, key: cacheKey, maxAge: cacheMaxAge) {
                    stations = cached.value
                    stationGroups = StationGrouping.buildGroups(stations)
                    isDataStale = true
                    applyFilter()
                    toastMessage = L10n.tr("stations.cache.toast")
                } else {
                    filteredStationGroups = []
                    state = .error(message)
                }
            } else {
                state = .success
                isDataStale = true
                toastMessage = message
            }
        }
    }

    /// 对缺少 products 的站点进行异步 enrich，拿到后局部刷新。
    private func enrichStationsIfNeeded() async {
        let unknownStations = stations.filter {
            $0.productsBitmask == nil && $0.productAtStop == nil
                && ($0.products == nil || $0.products?.isEmpty == true)
                && $0.stationMode == .unknown
        }
        guard !unknownStations.isEmpty else { return }

        let client = HafasClient()
        var didUpdate = false

        for station in unknownStations {
            guard let enriched = await ProductClassCache.shared.enrichStop(
                stopId: station.id, stopName: station.name, client: client
            ) else { continue }

            // 用 enriched 数据创建更新后的 StationModel
            if let idx = stations.firstIndex(where: { $0.id == station.id }) {
                let updated = StationModel(
                    id: station.id,
                    extId: station.extId,
                    globalId: station.globalId,
                    name: station.name,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    distanceMeters: station.distanceMeters,
                    type: station.type,
                    products: station.products,
                    productsBitmask: enriched.productsBitmask,
                    productAtStop: enriched.productAtStop,
                    category: station.category,
                    zone: station.zone,
                    zoneSource: station.zoneSource,
                    stationGroupId: station.stationGroupId
                )
                stations[idx] = updated
                didUpdate = true
            }
        }

        if didUpdate {
            stationGroups = StationGrouping.buildGroups(stations)
            applyFilter()
        }
    }

    /// 0.5 秒防抖，避免每次输入都立刻触发过滤。
    private func scheduleDebouncedFilter() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.searchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self.applyFilter()
        }
    }

    /// 本地过滤逻辑。
    private func applyFilter() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if keyword.isEmpty {
            filteredStationGroups = stationGroups
        } else {
            filteredStationGroups = stationGroups.filter { group in
                if group.baseName.localizedCaseInsensitiveContains(keyword) {
                    return true
                }
                return group.stations.contains { $0.name.localizedCaseInsensitiveContains(keyword) }
            }
        }

        state = filteredStationGroups.isEmpty ? .empty : .success
    }
}
