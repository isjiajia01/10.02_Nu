import SwiftUI
import MapKit

@MainActor
struct MapView: View {
    private enum Route: Hashable {
        case stationHub(StationGroupModel)
    }

    private let dependencies: AppDependencies
    @Binding private var pendingStationID: String?
    private let debugScenario: MapViewModel.DebugScenario

    @StateObject private var viewModel: MapViewModel
    @State private var navigationPath: [Route] = []

    init(
        viewModel: MapViewModel,
        pendingStationID: Binding<String?> = .constant(nil),
        debugScenario: MapViewModel.DebugScenario = .live,
        dependencies: AppDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? AppDependencies.live
        self.dependencies = resolvedDependencies
        self._pendingStationID = pendingStationID
        self.debugScenario = debugScenario
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.stationGroups.isEmpty {
                    ProgressView(L10n.tr("map.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isLocationDenied {
                    permissionDeniedView
                } else if let errorMessage = viewModel.errorMessage, viewModel.stationGroups.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("map.loadFailed.title"),
                        systemImage: "map",
                        description: Text(errorMessage)
                    )
                } else if viewModel.stationGroups.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("map.empty.title"),
                        systemImage: "tram",
                        description: Text(L10n.tr("map.empty.description"))
                    )
                } else {
                    List {
                        Section {
                            mapCard
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        if viewModel.usingFallbackLocation {
                            Section {
                                Label(
                                    L10n.tr("map.locationFallback"),
                                    systemImage: "location.slash"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Section(L10n.tr("map.nearbyStations")) {
                            ForEach(viewModel.stationGroups) { group in
                                NavigationLink(value: Route.stationHub(group)) {
                                    stationRow(group)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle(L10n.tr("map.title"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .stationHub(let group):
                    StationHubView(
                        group: group,
                        dependencies: dependencies
                    )
                }
            }
            .task {
                viewModel.start()
            }
            .onChange(of: debugScenario) { _, newValue in
                viewModel.setDebugScenario(newValue)
            }
            .onChange(of: viewModel.stationGroups) { _, _ in
                consumePendingStationDeepLinkIfPossible()
            }
            .onChange(of: pendingStationID) { _, _ in
                consumePendingStationDeepLinkIfPossible()
            }
        }
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView(
            L10n.tr("map.permissionDenied.title"),
            systemImage: "location.slash",
            description: Text(L10n.tr("map.permissionDenied.description"))
        )
    }

    private var mapCard: some View {
        Map(position: $viewModel.cameraPosition) {
            if viewModel.userCoordinate != nil {
                UserAnnotation()
            }

            ForEach(viewModel.stationGroups) { group in
                if let coordinate = group.mapCoordinate {
                    Marker(group.baseName, coordinate: coordinate)
                        .tint(markerTint(for: group))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("map.nearbyStations"))
                            .font(.headline.weight(.semibold))

                        Text(L10n.tr("map.minimal.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel(L10n.tr("map.recenter"))
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(12)
        }
    }

    private func stationRow(_ group: StationGroupModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.baseName)
                .font(.headline)

            Text(group.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(group.mergedHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func markerTint(for group: StationGroupModel) -> Color {
        switch group.mergedMode {
        case .bus:
            return .blue
        case .metro:
            return .green
        case .tog:
            return .red
        case .mixed:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private func consumePendingStationDeepLinkIfPossible() {
        guard let pendingStationID else { return }
        guard let group = viewModel.stationGroups.first(where: { group in
            group.stations.contains(where: { $0.id == pendingStationID || $0.extId == pendingStationID })
        }) else {
            return
        }

        navigationPath = [.stationHub(group)]
        self.pendingStationID = nil
    }
}

#Preview {
    let dependencies = AppDependencies.preview
    MapView(
        viewModel: dependencies.makeMapViewModel(),
        pendingStationID: .constant(nil),
        dependencies: dependencies
    )
}
