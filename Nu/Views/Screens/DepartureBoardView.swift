import SwiftUI

/// Departure board screen.
///
/// Uses `DepartureBoardViewModel` to fetch departures for a station.
/// Each item is rendered via `GlassDepartureCard`.
@MainActor
struct DepartureBoardView: View {
    private let stationId: String
    private let stationExtId: String?
    private let stationGlobalId: String?
    private let stationName: String?
    private let stationType: String?
    private let walkingDestinations: [WalkingETADestination]
    private let apiServiceForDetail: APIServiceProtocol
    @StateObject private var viewModel: DepartureBoardViewModel
    @StateObject private var favoritesManager: FavoritesManager
    @State private var isWalkingPanelExpanded = false

    init(
        stationId: String,
        stationExtId: String? = nil,
        stationGlobalId: String? = nil,
        stationName: String? = nil,
        stationType: String? = nil,
        walkingDestinations: [WalkingETADestination] = [],
        apiService: APIServiceProtocol? = nil,
        dependencies: AppDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? AppDependencies.live
        let resolvedAPIService = apiService ?? resolvedDependencies.apiService

        self.stationId = stationId
        self.stationExtId = stationExtId
        self.stationGlobalId = stationGlobalId
        self.stationName = stationName
        self.stationType = stationType
        self.walkingDestinations = walkingDestinations
        self.apiServiceForDetail = resolvedAPIService
        _viewModel = StateObject(wrappedValue: DepartureBoardViewModel(
            stationId: stationId,
            walkingDestinations: walkingDestinations,
            apiService: resolvedAPIService,
            locationManager: resolvedDependencies.locationManager,
            walkingETAService: resolvedDependencies.makeWalkingETAService()
        ))
        _favoritesManager = StateObject(wrappedValue: resolvedDependencies.favoritesManager)
    }

    var body: some View {
        Group {
            if viewModel.state == .idle || viewModel.state == .loading {
                ProgressView(L10n.tr("departures.loading"))
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    L10n.tr("common.loadFailed"),
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(errorMessage)
                )
            } else if viewModel.state == .empty {
                ContentUnavailableView(
                    L10n.tr("departures.empty.title"),
                    systemImage: "clock.badge.questionmark",
                    description: Text(L10n.tr("departures.empty.description"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.isDataStale {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text(L10n.tr("departures.cache.banner"))
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                        }

                        DepartureBoardWalkAndDelayCard(
                            walkingTimeTitleText: viewModel.walkingTimeTitleText,
                            walkingTimeDisplayText: viewModel.walkingTimeDisplayText,
                            walkingEstimateHintText: viewModel.walkingEstimateHintText,
                            sourceLabel: viewModel.walkTimeSource.displayName,
                            updateStatusText: viewModel.walkingUpdateStatusText,
                            departureDelayMinutes: viewModel.departureDelayMinutes,
                            departureDelayDisplayText: viewModel.departureDelayDisplayText,
                            activePreset: viewModel.activePreset,
                            isExpanded: isWalkingPanelExpanded,
                            onDelayChange: { newDelay in
                                viewModel.updateDepartureDelay(newDelay)
                            },
                            onPresetAtStation: {
                                viewModel.applyAlreadyInStationPreset()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    isWalkingPanelExpanded = false
                                }
                            },
                            onPresetOnTheWay: {
                                viewModel.applyOnTheWayPreset()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    isWalkingPanelExpanded = false
                                }
                            },
                            onToggleExpand: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                    isWalkingPanelExpanded.toggle()
                                }
                            }
                        )

                        DepartureBoardReliabilityLegendView()

                        ForEach(viewModel.departures) { departure in
                            if let ref = departure.journeyRef, !ref.isEmpty {
                                NavigationLink(
                                    destination: JourneyDetailView(
                                        journeyID: ref,
                                        operationDate: departure.rtDate ?? departure.date,
                                        fallbackStops: departure.passListStops,
                                        lineName: departure.name,
                                        transportType: departure.type,
                                        directionText: departure.direction,
                                        currentStopName: departure.stop,
                                        plannedTime: departure.time,
                                        realtimeTime: departure.rtTime,
                                        apiService: apiServiceForDetail
                                    )
                                ) {
                                    GlassDepartureCard(
                                        departure: departure,
                                        catchProbabilityText: viewModel.catchProbabilityDisplay(for: departure),
                                        directionText: viewModel.directionText(for: departure),
                                        directionStyle: viewModel.directionChipStyle(for: departure)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                GlassDepartureCard(
                                    departure: departure,
                                    catchProbabilityText: viewModel.catchProbabilityDisplay(for: departure),
                                    directionText: viewModel.directionText(for: departure),
                                    directionStyle: viewModel.directionChipStyle(for: departure)
                                )
                            }
                        }
                    }
                    .padding()
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
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.indigo.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle(L10n.tr("departures.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let nameFromData = stationName ?? viewModel.departures.first?.stop
                    let typeFromData = stationType ?? viewModel.departures.first?.type
                    favoritesManager.toggleFavorite(
                        stationId: stationId,
                        extId: stationExtId,
                        globalId: stationGlobalId,
                        stationName: nameFromData,
                        stationType: typeFromData
                    )
                }
                label: {
                    Label(
                        L10n.tr("departures.favorite.accessibility"),
                        systemImage: favoritesManager.isFavorite(stationId) ? "heart.fill" : "heart"
                    )
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
                }
            }
        }
        .task {
            await viewModel.fetchDepartures()
        }
        .refreshable {
            await viewModel.fetchDepartures()
        }
        .onDisappear {
            viewModel.stopOnTheWayUpdates()
        }
    }
}

#Preview {
    NavigationStack {
        DepartureBoardView(stationId: "8600622", apiService: MockAPIService())
    }
}
