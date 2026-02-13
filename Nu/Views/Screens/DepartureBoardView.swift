import SwiftUI

/// 发车板页面。
///
/// 说明：
/// - 使用 `DepartureBoardViewModel` 拉取指定站点发车数据。
/// - 每一项通过 `GlassDepartureCard` 呈现。
struct DepartureBoardView: View {
    private let stationId: String
    private let stationExtId: String?
    private let stationGlobalId: String?
    private let stationName: String?
    private let stationType: String?
    private let apiServiceForDetail: APIServiceProtocol
    @StateObject private var viewModel: DepartureBoardViewModel
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var isWalkingPanelExpanded = false

    /// - Parameters:
    ///   - stationId: 站点 ID。
    ///   - apiService: 可注入真实服务或 Mock 服务。
    init(
        stationId: String,
        stationExtId: String? = nil,
        stationGlobalId: String? = nil,
        stationName: String? = nil,
        stationType: String? = nil,
        apiService: APIServiceProtocol = RejseplanenAPIService()
    ) {
        self.stationId = stationId
        self.stationExtId = stationExtId
        self.stationGlobalId = stationGlobalId
        self.stationName = stationName
        self.stationType = stationType
        self.apiServiceForDetail = apiService
        _viewModel = StateObject(wrappedValue: DepartureBoardViewModel(stationId: stationId, apiService: apiService))
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

                        WalkingSimulationCard(
                            walkingMinutes: viewModel.simulatedWalkingTime
                            ,
                            sourceLabel: viewModel.walkTimeSource.displayName,
                            intervalText: viewModel.walkingTimeIntervalText,
                            updateStatusText: viewModel.walkingUpdateStatusText,
                            activePreset: viewModel.activePreset,
                            isExpanded: isWalkingPanelExpanded
                        ) { newValue in
                            viewModel.updateSimulatedWalkingTime(newValue)
                        } onPresetAtStation: {
                            viewModel.applyAlreadyInStationPreset()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isWalkingPanelExpanded = false
                            }
                        } onPresetOnTheWay: {
                            viewModel.applyOnTheWayPreset()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isWalkingPanelExpanded = false
                            }
                        } onToggleExpand: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isWalkingPanelExpanded.toggle()
                            }
                        }

                        ReliabilityLegendView()

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
                                        catchProbabilityText: viewModel.catchProbabilityDisplay(for: departure)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                GlassDepartureCard(
                                    departure: departure,
                                    catchProbabilityText: viewModel.catchProbabilityDisplay(for: departure)
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
                } label: {
                    Image(systemName: favoritesManager.isFavorite(stationId) ? "heart.fill" : "heart")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel(L10n.tr("departures.favorite.accessibility"))
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

private struct WalkingSimulationCard: View {
    private let walkingMinutes: Double
    private let sourceLabel: String
    private let intervalText: String
    private let updateStatusText: String?
    private let activePreset: DepartureBoardViewModel.WalkPreset?
    private let isExpanded: Bool
    private let onChange: (Double) -> Void
    private let onPresetAtStation: () -> Void
    private let onPresetOnTheWay: () -> Void
    private let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("departures.walking.label"), systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(L10n.tr("departures.walking.minutesInterval", Int(walkingMinutes), intervalText))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                Button(L10n.tr("departures.walking.preset.inStation")) {
                    onPresetAtStation()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(activePreset == .alreadyInStation ? .green : .secondary.opacity(0.35))

                Button(L10n.tr("departures.walking.preset.onTheWay")) {
                    onPresetOnTheWay()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(activePreset == .onTheWay ? .blue : .secondary.opacity(0.35))

                Text(sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let updateStatusText {
                    Text(updateStatusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer()

                Button(isExpanded ? L10n.tr("common.collapse") : L10n.tr("common.adjust")) {
                    onToggleExpand()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isExpanded {
                Slider(
                    value: Binding(
                        get: { walkingMinutes },
                        set: { onChange($0) }
                    ),
                    in: 1...20,
                    step: 1
                ) {
                    Text(L10n.tr("departures.walking.manual"))
                } minimumValueLabel: {
                    Text("1")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("20")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityValue(L10n.tr("departures.walking.accessibility.value", Int(walkingMinutes)))
                .accessibilityHint(L10n.tr("departures.walking.accessibility.hint"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
    }

    init(
        walkingMinutes: Double,
        sourceLabel: String,
        intervalText: String,
        updateStatusText: String?,
        activePreset: DepartureBoardViewModel.WalkPreset?,
        isExpanded: Bool,
        onChange: @escaping (Double) -> Void,
        onPresetAtStation: @escaping () -> Void,
        onPresetOnTheWay: @escaping () -> Void,
        onToggleExpand: @escaping () -> Void
    ) {
        self.walkingMinutes = walkingMinutes
        self.sourceLabel = sourceLabel
        self.intervalText = intervalText
        self.updateStatusText = updateStatusText
        self.activePreset = activePreset
        self.isExpanded = isExpanded
        self.onChange = onChange
        self.onPresetAtStation = onPresetAtStation
        self.onPresetOnTheWay = onPresetOnTheWay
        self.onToggleExpand = onToggleExpand
    }
}

private struct ReliabilityLegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            legendItem(signal: .high, detail: "> 0.8")
            legendItem(signal: .medium, detail: "0.5-0.8")
            legendItem(signal: .low, detail: "< 0.5")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("departures.reliability.legend.label"))
        .accessibilityValue(L10n.tr("departures.reliability.legend.value"))
    }

    @ViewBuilder
    private func legendItem(signal: ReliabilitySignal, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(signal.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(signal.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 24)
    }
}

#Preview {
    NavigationStack {
        DepartureBoardView(stationId: "8600622", apiService: MockAPIService())
    }
}
