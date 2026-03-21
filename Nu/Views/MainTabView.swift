import SwiftUI

/// 主容器页面。
///
/// 说明：
/// - 采用 Tab 结构，符合规范中的 dashboard 建议。
/// - 从 `AppDependencies` 注入共享服务，避免在根视图内重复创建长期依赖。
struct MainTabView: View {
    private let dependencies: AppDependencies

    @StateObject private var locationManager: LocationManager
    @StateObject private var diagnostics: DiagnosticsStore
    @StateObject private var nearbyViewModel: NearbyStationsViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _locationManager = StateObject(wrappedValue: dependencies.locationManager)
        _diagnostics = StateObject(wrappedValue: dependencies.diagnosticsStore)
        _nearbyViewModel = StateObject(wrappedValue: dependencies.makeNearbyStationsViewModel())
    }

    var body: some View {
        TabView {
            NearbyStationsView(
                viewModel: nearbyViewModel,
                dependencies: dependencies
            )
                .tabItem {
                    Label(L10n.tr("tab.stations"), systemImage: "tram.fill")
                }

            FavoritesView(dependencies: dependencies)
                .tabItem {
                    Label(L10n.tr("tab.favorites"), systemImage: "heart.fill")
                }

            NavigationStack {
                MapView(
                    apiService: dependencies.apiService,
                    locationManager: locationManager
                )
            }
            .tabItem {
                Label(L10n.tr("tab.map"), systemImage: "map")
            }
        }
        .tint(.indigo)
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

#Preview {
    MainTabView(dependencies: .preview)
}
