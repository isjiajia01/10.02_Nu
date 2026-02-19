import SwiftUI

/// 主容器页面。
///
/// 说明：
/// - 采用 Tab 结构，符合规范中的 dashboard 建议。
/// - 地图页暂用占位，可在后续接入 MapKit。
struct MainTabView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var diagnostics = DiagnosticsStore.shared

    var body: some View {
        TabView {
            NearbyStationsView(
                viewModel: NearbyStationsViewModel(
                    apiService: RejseplanenAPIService(),
                    locationManager: locationManager
                )
            )
            .tabItem {
                Label(L10n.tr("tab.stations"), systemImage: "tram.fill")
            }

            FavoritesView()
            .tabItem {
                Label(L10n.tr("tab.favorites"), systemImage: "heart.fill")
            }

            NavigationStack {
                MapView(apiService: RejseplanenAPIService(), locationManager: locationManager)
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
    MainTabView()
}
