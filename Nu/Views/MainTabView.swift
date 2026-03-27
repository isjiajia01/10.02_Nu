import SwiftUI

/// 主容器页面。
///
/// 说明：
/// - 采用 Tab 结构，符合规范中的 dashboard 建议。
/// - 从 `AppDependencies` 注入共享服务，避免在根视图内重复创建长期依赖。
struct MainTabView: View {
    private enum TabID: Hashable {
        case stations
        case favorites
        case map
        case settings
    }

    private let dependencies: AppDependencies

    @StateObject private var diagnostics: DiagnosticsStore
    @StateObject private var nearbyViewModel: NearbyStationsViewModel
    @StateObject private var mapViewModel: MapViewModel
    @State private var selectedTab = Self.initialTab
    @State private var pendingMapStationID = Self.initialStationID
    @State private var mapDebugScenario = Self.initialMapDebugScenario

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _diagnostics = StateObject(wrappedValue: dependencies.diagnosticsStore)
        _nearbyViewModel = StateObject(wrappedValue: dependencies.makeNearbyStationsViewModel())
        _mapViewModel = StateObject(
            wrappedValue: dependencies.makeMapViewModel(debugScenario: Self.initialMapDebugScenario)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyStationsView(
                viewModel: nearbyViewModel,
                dependencies: dependencies
            )
                .tag(TabID.stations)
                .tabItem {
                    Label(L10n.tr("tab.stations"), systemImage: "tram.fill")
                }

            FavoritesView(dependencies: dependencies)
                .tag(TabID.favorites)
                .tabItem {
                    Label(L10n.tr("tab.favorites"), systemImage: "heart.fill")
                }

            MapView(
                viewModel: mapViewModel,
                pendingStationID: $pendingMapStationID,
                debugScenario: mapDebugScenario,
                dependencies: dependencies
            )
                .tag(TabID.map)
                .tabItem {
                    Label(L10n.tr("tab.map"), systemImage: "map.fill")
                }

            SettingsView()
                .tag(TabID.settings)
                .tabItem {
                    Label(L10n.tr("tab.settings"), systemImage: "gearshape")
                }
        }
        .tint(.indigo)
        .onOpenURL { url in
            guard let action = DebugDeepLink(url: url) else { return }
            selectedTab = .map
            if let scenario = action.scenario {
                mapDebugScenario = scenario
            }
            if let stationID = action.stationID {
                pendingMapStationID = stationID
            }
        }
        .overlay(alignment: .top) {
            #if DEBUG
            if let warning = diagnostics.latestWarning {
                StatusToast(message: warning) {
                    diagnostics.clearWarning()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
        }
    }
}

private extension MainTabView {
    private static var initialTab: TabID {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if initialStationID != nil || initialMapDebugScenario != .live {
            return .map
        }
        if arguments.contains("--open-map-tab") {
            return .map
        }
        if arguments.contains("--open-settings-tab") {
            return .settings
        }
        #endif
        return .stations
    }

    private static var initialStationID: String? {
        #if DEBUG
        return argumentValue(for: "--map-debug-station-id")
        #else
        return nil
        #endif
    }

    private static var initialMapDebugScenario: MapViewModel.DebugScenario {
        #if DEBUG
        if let raw = argumentValue(for: "--map-debug-state") {
            return MapViewModel.DebugScenario(rawValue: raw) ?? .live
        }
        return .live
        #else
        return .live
        #endif
    }

    private static func argumentValue(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

private struct DebugDeepLink {
    let scenario: MapViewModel.DebugScenario?
    let stationID: String?

    init?(url: URL) {
        guard url.scheme == "nu-debug", url.host == "map" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if pathComponents.first == "station" {
            self.stationID = pathComponents.dropFirst().first ?? components?.queryItems?.first(where: {
                $0.name == "id"
            })?.value
        } else {
            self.stationID = components?.queryItems?.first(where: { $0.name == "stationId" })?.value
        }

        if let rawScenario = components?.queryItems?.first(where: { $0.name == "state" })?.value {
            self.scenario = MapViewModel.DebugScenario(rawValue: rawScenario)
        } else {
            self.scenario = nil
        }
    }
}

#Preview {
    MainTabView(dependencies: .preview)
}
