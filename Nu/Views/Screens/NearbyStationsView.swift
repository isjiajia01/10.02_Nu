import SwiftUI

/// 附近站点主界面（卡片流布局）。
///
/// 设计目标：
/// - 使用玻璃拟态卡片替代传统分割线列表。
/// - 强调“附近 + 导向”信息密度。
struct NearbyStationsView: View {
    @StateObject private var viewModel: NearbyStationsViewModel

    init(viewModel: NearbyStationsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景层：极淡渐变，衬托毛玻璃材质。
                LinearGradient(
                    colors: [Color(uiColor: .systemGroupedBackground), Color.blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if viewModel.state == .idle || viewModel.state == .loading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        L10n.tr("common.loadFailed"),
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if viewModel.state == .empty {
                    ContentUnavailableView(
                        L10n.tr("stations.empty.title"),
                        systemImage: "location.slash",
                        description: Text(L10n.tr("stations.empty.description"))
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Color.clear.frame(height: 10)

                            if viewModel.isDataStale {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text(L10n.tr("stations.cache.banner"))
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                            }

                            ForEach(viewModel.filteredStationGroups) { group in
                                NavigationLink(
                                    destination: StationHubView(group: group)
                                ) {
                                    GlassStationCard(group: group)
                                }
                                .buttonStyle(.plain)
                            }

                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 16)
                    }
                    .refreshable {
                        await viewModel.refreshNearbyStations()
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast = viewModel.toastMessage {
                    StatusToast(message: toast) {
                        viewModel.toastMessage = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(L10n.tr("stations.title"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText, prompt: L10n.tr("stations.search.prompt"))
            .task {
                viewModel.start()
            }
        }
    }
}

#Preview {
    NearbyStationsView(
        viewModel: NearbyStationsViewModel(
            apiService: MockAPIService(),
            locationManager: LocationManager()
        )
    )
}
