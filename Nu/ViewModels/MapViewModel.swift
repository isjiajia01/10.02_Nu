import Foundation
import CoreLocation
import Combine
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {
    enum DebugScenario: String, Equatable {
        case live
        case empty
        case failure
        case denied
    }

    @Published private(set) var stationGroups: [StationGroupModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var usingFallbackLocation = false
    @Published var cameraPosition: MapCameraPosition
    @Published private(set) var isLocationDenied = false

    private let apiService: APIServiceProtocol
    private let locationManager: LocationManaging
    private var debugScenario: DebugScenario
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false
    private var hasLoadedPreciseLocation = false
    private var loadTask: Task<Void, Never>?

    private let fallbackCoordinate = CLLocationCoordinate2D(
        latitude: 55.676098,
        longitude: 12.568337
    )

    init(
        apiService: APIServiceProtocol = RejseplanenAPIService(),
        locationManager: LocationManaging,
        debugScenario: DebugScenario = .live
    ) {
        self.apiService = apiService
        self.locationManager = locationManager
        self.debugScenario = debugScenario
        self.cameraPosition = .region(
            MKCoordinateRegion(
                center: fallbackCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
    }

    deinit {
        loadTask?.cancel()
        cancellables.removeAll()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard debugScenario == .live else {
            applyDebugScenario(debugScenario)
            return
        }

        observeLocation()
        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()

        if let currentLocation = locationManager.currentLocation {
            enqueueLoad(around: currentLocation.coordinate, usesFallback: false)
            return
        }

        loadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            guard self.stationGroups.isEmpty else { return }
            await self.loadStations(around: self.fallbackCoordinate, usesFallback: true)
        }
    }

    func refresh() async {
        guard debugScenario == .live else {
            applyDebugScenario(debugScenario)
            return
        }

        if let currentLocation = locationManager.currentLocation {
            await loadStations(around: currentLocation.coordinate, usesFallback: false)
        } else {
            locationManager.requestAuthorization()
            locationManager.startUpdatingLocation()
            await loadStations(around: fallbackCoordinate, usesFallback: true)
        }
    }

    func setDebugScenario(_ scenario: DebugScenario) {
        debugScenario = scenario
        hasLoadedPreciseLocation = false

        if hasStarted {
            if scenario == .live {
                stationGroups = []
                errorMessage = nil
                usingFallbackLocation = false
                isLocationDenied = false
                startLiveFlow()
            } else {
                applyDebugScenario(scenario)
            }
        }
    }

    private func startLiveFlow() {
        observeLocation()
        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()
        enqueueLoad(around: fallbackCoordinate, usesFallback: true)
    }

    private func observeLocation() {
        cancellables.removeAll()

        locationManager.currentLocationPublisher
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self else { return }
                guard !self.hasLoadedPreciseLocation else { return }
                self.enqueueLoad(around: location.coordinate, usesFallback: false)
            }
            .store(in: &cancellables)

        locationManager.authorizationStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isLocationDenied = status == .denied || status == .restricted
                guard status == .denied || status == .restricted else { return }
                self.enqueueLoad(around: self.fallbackCoordinate, usesFallback: true)
            }
            .store(in: &cancellables)
    }

    private func enqueueLoad(
        around coordinate: CLLocationCoordinate2D,
        usesFallback: Bool
    ) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadStations(around: coordinate, usesFallback: usesFallback)
        }
    }

    private func loadStations(
        around coordinate: CLLocationCoordinate2D,
        usesFallback: Bool
    ) async {
        isLoading = true
        errorMessage = nil
        isLocationDenied = false
        usingFallbackLocation = usesFallback
        userCoordinate = usesFallback ? nil : coordinate

        do {
            let stations = try await apiService.fetchNearbyStops(
                coordX: coordinate.longitude,
                coordY: coordinate.latitude,
                radiusMeters: 1500,
                maxNo: 20
            )

            let groups = StationGrouping.buildGroups(stations)
            stationGroups = groups
            cameraPosition = .region(makeRegion(center: coordinate, groups: groups))
            persistDebugCaptureIfNeeded(groups: groups)

            if usesFallback {
                errorMessage = L10n.tr("map.locationFallback")
            } else {
                hasLoadedPreciseLocation = true
                locationManager.stopUpdatingLocation()
            }
        } catch {
            stationGroups = []
            cameraPosition = .region(makeRegion(center: coordinate, groups: []))
            errorMessage = AppErrorPresenter.message(for: error, context: .map)
        }

        isLoading = false
    }

    private func applyDebugScenario(_ scenario: DebugScenario) {
        loadTask?.cancel()
        cancellables.removeAll()
        locationManager.stopUpdatingLocation()

        isLoading = false
        userCoordinate = nil
        usingFallbackLocation = false
        isLocationDenied = false
        cameraPosition = .region(
            MKCoordinateRegion(
                center: fallbackCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )

        switch scenario {
        case .live:
            break
        case .empty:
            stationGroups = []
            errorMessage = nil
        case .failure:
            stationGroups = []
            errorMessage = L10n.tr("map.loadFailed.description")
        case .denied:
            stationGroups = []
            errorMessage = nil
            isLocationDenied = true
        }
    }

    private func persistDebugCaptureIfNeeded(groups: [StationGroupModel]) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--map-debug-capture-live-stations") else { return }

        let stationIDs = groups.flatMap(\.stations).map(\.id)
        let stationNames = groups.map(\.baseName)
        UserDefaults.standard.set(stationIDs, forKey: "nu.debug.map.stationIDs")
        UserDefaults.standard.set(stationNames, forKey: "nu.debug.map.stationNames")
        UserDefaults.standard.set(stationIDs.first, forKey: "nu.debug.map.firstStationID")
        UserDefaults.standard.set(stationNames.first, forKey: "nu.debug.map.firstStationName")
        #endif
    }

    private func makeRegion(
        center: CLLocationCoordinate2D,
        groups: [StationGroupModel]
    ) -> MKCoordinateRegion {
        let coordinates = groups.compactMap(\.mapCoordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let minLat = min(latitudes.min() ?? center.latitude, center.latitude)
        let maxLat = max(latitudes.max() ?? center.latitude, center.latitude)
        let minLon = min(longitudes.min() ?? center.longitude, center.longitude)
        let maxLon = max(longitudes.max() ?? center.longitude, center.longitude)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.6),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.6)
            )
        )
    }
}

extension StationGroupModel {
    var mapCoordinate: CLLocationCoordinate2D? {
        let entrance = bestEntrance()
        return CLLocationCoordinate2D(
            latitude: entrance.latitude,
            longitude: entrance.longitude
        )
    }
}
