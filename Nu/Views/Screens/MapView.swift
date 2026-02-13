import SwiftUI
import MapKit
import UIKit

struct MapView: View {
    @State private var stationGroups: [StationGroupModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var focusCoordinate: CLLocationCoordinate2D?
    @State private var focusToken: Int = 0
    @State private var selectedGroup: StationGroupModel?
    @State private var lastRefreshQuery: MapRefreshQuery?
    @State private var pendingQuery: MapRefreshQuery?
    @State private var showSearchAreaButton = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var inFlightFetchTask: Task<Void, Never>?

    @StateObject private var locationManager = LocationManager()
    private let apiService: APIServiceProtocol

    init(apiService: APIServiceProtocol? = nil) {
        self.apiService = apiService ?? RejseplanenAPIService()
    }

    var body: some View {
        ZStack {
            StationGroupsMapView(
                groups: stationGroups,
                focusCoordinate: focusCoordinate,
                focusToken: focusToken,
                onViewportChange: handleViewportChange(region:userGesture:)
            ) { group in
                selectedGroup = group
            }
            .ignoresSafeArea()

            if isLoading {
                ProgressView(L10n.tr("map.loading"))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.9))
                    )
            }

            if let errorMessage, stationGroups.isEmpty {
                ContentUnavailableView(
                    L10n.tr("map.loadFailed.title"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
            }

            if let errorMessage, !stationGroups.isEmpty {
                VStack {
                    StatusToast(message: errorMessage) {
                        self.errorMessage = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            if isLocationDenied {
                permissionDeniedOverlay
            }

            if showSearchAreaButton, !isLoading {
                VStack {
                    HStack {
                        Spacer()
                        Button(L10n.tr("map.searchThisArea")) {
                            triggerManualSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(L10n.tr("map.searchThisArea"))
                        .accessibilityHint(L10n.tr("map.searchThisArea.hint"))
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle(L10n.tr("map.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedGroup) { group in
            StationHubView(group: group)
        }
        .task {
            await startMapFlow()
        }
        .onChange(of: locationManager.authorizationStatus) { _, newValue in
            guard newValue == .authorizedAlways || newValue == .authorizedWhenInUse else { return }
            Task { await loadStations() }
        }
        .onDisappear {
            debounceTask?.cancel()
            inFlightFetchTask?.cancel()
        }
    }

    private var isLocationDenied: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    private var permissionDeniedOverlay: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                L10n.tr("map.permissionDenied.title"),
                systemImage: "location.slash",
                description: Text(L10n.tr("map.permissionDenied.description"))
            )
            Button(L10n.tr("map.permissionDenied.openSettings")) {
                openAppSettings()
            }
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(L10n.tr("map.permissionDenied.openSettings.hint"))
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
    }

    private func startMapFlow() async {
        errorMessage = nil
        isLoading = true

        locationManager.requestAuthorization()
        locationManager.startUpdatingLocation()
        await loadStations()
    }

    private func loadStations() async {
        let fallbackLon = 12.568337
        let fallbackLat = 55.676098

        let rawLon = locationManager.currentLocation?.coordinate.longitude
        let rawLat = locationManager.currentLocation?.coordinate.latitude
        let shouldUseFallback = !isLikelyInDenmark(latitude: rawLat, longitude: rawLon)

        let coordX = shouldUseFallback ? fallbackLon : (rawLon ?? fallbackLon)
        let coordY = shouldUseFallback ? fallbackLat : (rawLat ?? fallbackLat)

        if shouldUseFallback {
            errorMessage = L10n.tr("map.locationFallback")
        }

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

            if !shouldUseFallback {
                errorMessage = nil
            }

            if let first = stationGroups.first?.bestEntrance() {
                focusCoordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
                focusToken += 1
            }
        } catch {
            let message = AppErrorPresenter.message(for: error, context: .map)
            errorMessage = message
            if stationGroups.isEmpty {
                stationGroups = []
            }
        }

        isLoading = false
    }

    private func isLikelyInDenmark(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else { return false }
        return (54.0...58.0).contains(latitude) && (7.0...16.5).contains(longitude)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func handleViewportChange(region: MKCoordinateRegion, userGesture: Bool) {
        guard userGesture else { return }
        let nextQuery = MapRefreshQuery.from(center: region.center, span: region.span)
        guard shouldRefresh(from: lastRefreshQuery, to: nextQuery) else { return }

        pendingQuery = nextQuery
        showSearchAreaButton = true
        scheduleAutoRefresh(with: nextQuery)
    }

    private func scheduleAutoRefresh(with query: MapRefreshQuery) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await runViewportRefresh(query)
        }
    }

    private func triggerManualSearch() {
        guard let query = pendingQuery else { return }
        debounceTask?.cancel()
        Task { await runViewportRefresh(query) }
    }

    private func runViewportRefresh(_ query: MapRefreshQuery) async {
        inFlightFetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        showSearchAreaButton = false

        let task = Task {
            do {
                try Task.checkCancellation()
                let fetched = try await apiService.fetchNearbyStops(
                    coordX: query.center.longitude,
                    coordY: query.center.latitude,
                    radiusMeters: query.radiusMeters,
                    maxNo: query.maxNo
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    stationGroups = StationGrouping.buildGroups(fetched)
                    lastRefreshQuery = query
                    pendingQuery = nil
                    isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = AppErrorPresenter.message(for: error, context: .map)
                    isLoading = false
                }
            }
        }
        inFlightFetchTask = task
    }

    private func shouldRefresh(from previous: MapRefreshQuery?, to next: MapRefreshQuery) -> Bool {
        guard let previous else { return true }
        return previous.centerDistanceMeters(to: next) > 200 || previous.spanDeltaRatio(to: next) > 0.30
    }
}

private struct MapRefreshQuery {
    let center: CLLocationCoordinate2D
    let latitudeDelta: Double
    let longitudeDelta: Double
    let radiusMeters: Int
    let maxNo: Int

    static func from(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> MapRefreshQuery {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let latEdge = CLLocation(latitude: center.latitude + span.latitudeDelta / 2, longitude: center.longitude)
        let lonEdge = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta / 2)

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
}

private struct StationGroupsMapView: UIViewRepresentable {
    let groups: [StationGroupModel]
    let focusCoordinate: CLLocationCoordinate2D?
    let focusToken: Int
    let onViewportChange: (MKCoordinateRegion, Bool) -> Void
    let onSelectGroup: (StationGroupModel) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectGroup: onSelectGroup, onViewportChange: onViewportChange)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(StationBadgeAnnotationView.self, forAnnotationViewWithReuseIdentifier: StationBadgeAnnotationView.reuseID)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseID)
        mapView.mapType = .mutedStandard
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.syncAnnotations(on: mapView, with: groups)
        if context.coordinator.lastFocusToken != focusToken, let focusCoordinate {
            context.coordinator.lastFocusToken = focusToken
            let region = MKCoordinateRegion(
                center: focusCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
            mapView.setRegion(region, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let clusterReuseID = "StationClusterView"

        private let onSelectGroup: (StationGroupModel) -> Void
        private let onViewportChange: (MKCoordinateRegion, Bool) -> Void
        fileprivate var lastFocusToken: Int = -1
        private var imageCache: [String: UIImage] = [:]

        init(
            onSelectGroup: @escaping (StationGroupModel) -> Void,
            onViewportChange: @escaping (MKCoordinateRegion, Bool) -> Void
        ) {
            self.onSelectGroup = onSelectGroup
            self.onViewportChange = onViewportChange
        }

        func syncAnnotations(on mapView: MKMapView, with groups: [StationGroupModel]) {
            let existing = mapView.annotations.compactMap { $0 as? StationGroupAnnotation }
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.group.id, $0) })
            let targetIDs = Set(groups.map(\.id))

            let toRemove = existing.filter { !targetIDs.contains($0.group.id) }
            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }

            var toAdd: [StationGroupAnnotation] = []
            for group in groups {
                if existingByID[group.id] == nil {
                    toAdd.append(StationGroupAnnotation(group: group))
                } else if let annotation = existingByID[group.id] {
                    annotation.group = group
                }
            }
            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterReuseID, for: cluster) as! MKMarkerAnnotationView
                view.clusteringIdentifier = nil
                view.canShowCallout = false
                view.displayPriority = .defaultHigh
                view.glyphText = "\(cluster.memberAnnotations.count)"

                let mode = clusterMode(from: cluster.memberAnnotations)
                let style = StationModeVisualStyle(mode: mode)
                view.markerTintColor = style.markerTint
                view.glyphTintColor = style.glyphTint
                return view
            }

            guard let stationAnnotation = annotation as? StationGroupAnnotation else {
                return nil
            }

            let view = mapView.dequeueReusableAnnotationView(withIdentifier: StationBadgeAnnotationView.reuseID, for: stationAnnotation) as! StationBadgeAnnotationView
            view.annotation = stationAnnotation
            view.clusteringIdentifier = "station-group"
            let style = StationModeVisualStyle(mode: stationAnnotation.group.mergedMode)
            view.applyStyle(style: style, image: cachedImage(symbolName: style.symbolName))
            view.isAccessibilityElement = true
            view.accessibilityLabel = "\(stationAnnotation.group.baseName), \(stationAnnotation.group.subtitle)"
            view.accessibilityHint = L10n.tr("map.pin.accessibility.hint")
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }

            guard let annotation = view.annotation as? StationGroupAnnotation else { return }
            onSelectGroup(annotation.group)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            onViewportChange(mapView.region, mapView.isRegionChangeFromUserInteraction)
        }

        private func cachedImage(symbolName: String) -> UIImage {
            if let cached = imageCache[symbolName] {
                return cached
            }
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
            imageCache[symbolName] = image
            return image
        }

        private func clusterMode(from members: [MKAnnotation]) -> StationModel.StationMode {
            let stationModes = members.compactMap { ($0 as? StationGroupAnnotation)?.group.mergedMode }
            guard !stationModes.isEmpty else { return .unknown }

            let singles = stationModes.reduce(into: Set<StationModel.StationMode.SingleMode>()) { acc, mode in
                switch mode {
                case .bus: acc.insert(.bus)
                case .metro: acc.insert(.metro)
                case .tog: acc.insert(.tog)
                case .mixed(let set): acc.formUnion(set)
                case .unknown: break
                }
            }
            if singles.count > 1 { return .mixed(singles) }
            if let single = singles.first {
                switch single {
                case .bus: return .bus
                case .metro: return .metro
                case .tog: return .tog
                }
            }
            return .unknown
        }
    }
}

private final class StationGroupAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    var group: StationGroupModel {
        didSet {
            title = group.baseName
            let best = group.bestEntrance()
            coordinate = CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
        }
    }

    init(group: StationGroupModel) {
        self.group = group
        let best = group.bestEntrance()
        self.coordinate = CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
        self.title = group.baseName
        super.init()
    }
}

private final class StationBadgeAnnotationView: MKAnnotationView {
    static let reuseID = "StationBadgeAnnotationView"

    private let badgeView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
    private let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        centerOffset = CGPoint(x: 0, y: -15)
        canShowCallout = false
        displayPriority = .defaultHigh
        collisionMode = .rectangle

        badgeView.layer.cornerRadius = 10
        badgeView.layer.masksToBounds = true
        badgeView.frame = bounds
        addSubview(badgeView)

        imageView.contentMode = .scaleAspectFit
        imageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStyle(style: StationModeVisualStyle, image: UIImage) {
        badgeView.backgroundColor = UIColor(style.badgeBackground)
        imageView.image = image.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = UIColor(style.iconColor)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let changes = {
            self.transform = selected ? CGAffineTransform(scaleX: 1.32, y: 1.32) : .identity
            self.layer.shadowOpacity = selected ? 0.22 : 0
            self.layer.shadowRadius = selected ? 8 : 0
            self.layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }
}

private extension MKMapView {
    var isRegionChangeFromUserInteraction: Bool {
        guard let firstSubview = subviews.first else { return false }
        let recognizers = firstSubview.gestureRecognizers ?? []
        return recognizers.contains {
            $0.state == .began || $0.state == .changed || $0.state == .ended
        }
    }
}
