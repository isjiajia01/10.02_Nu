import SwiftUI

/// Departure board screen.
///
/// Uses `DepartureBoardViewModel` to fetch departures for a station.
/// Each item is rendered via `GlassDepartureCard`.
struct DepartureBoardView: View {
    private let stationId: String
    private let stationExtId: String?
    private let stationGlobalId: String?
    private let stationName: String?
    private let stationType: String?
    private let walkingDestinations: [WalkingETADestination]
    private let apiServiceForDetail: APIServiceProtocol
    @StateObject private var viewModel: DepartureBoardViewModel
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var isWalkingPanelExpanded = false

    init(
        stationId: String,
        stationExtId: String? = nil,
        stationGlobalId: String? = nil,
        stationName: String? = nil,
        stationType: String? = nil,
        walkingDestinations: [WalkingETADestination] = [],
        apiService: APIServiceProtocol = RejseplanenAPIService()
    ) {
        self.stationId = stationId
        self.stationExtId = stationExtId
        self.stationGlobalId = stationGlobalId
        self.stationName = stationName
        self.stationType = stationType
        self.walkingDestinations = walkingDestinations
        self.apiServiceForDetail = apiService
        _viewModel = StateObject(wrappedValue: DepartureBoardViewModel(
            stationId: stationId,
            walkingDestinations: walkingDestinations,
            apiService: apiService
        ))
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

                        WalkAndDelayCard(
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

// MARK: - Walk & Delay Card

/// Top card showing walk ETA (read-only) + departure delay (user input).
private struct WalkAndDelayCard: View {
    let walkingTimeTitleText: String
    let walkingTimeDisplayText: String
    let walkingEstimateHintText: String?
    let sourceLabel: String
    let updateStatusText: String?
    let departureDelayMinutes: Int
    let departureDelayDisplayText: String
    let activePreset: DepartureBoardViewModel.WalkPreset?
    let isExpanded: Bool
    let onDelayChange: (Int) -> Void
    let onPresetAtStation: () -> Void
    let onPresetOnTheWay: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Walk time (system-estimated, read-only)
            HStack {
                Label(walkingTimeTitleText, systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(walkingTimeDisplayText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            if let walkingEstimateHintText {
                Text(walkingEstimateHintText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Departure delay display
            HStack {
                Label(L10n.tr("departures.walking.delay.label"), systemImage: "clock.arrow.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(departureDelayDisplayText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            // Presets row
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
                // Departure delay presets (one-tap)
                HStack(spacing: 8) {
                    ForEach([0, 5, 10], id: \.self) { preset in
                        Button(delayPresetLabel(preset)) {
                            onDelayChange(preset)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(departureDelayMinutes == preset ? .blue : .secondary.opacity(0.3))
                    }
                    Spacer()
                }

                // Fine-tune slider for departure delay
                Slider(
                    value: Binding(
                        get: { Double(departureDelayMinutes) },
                        set: { onDelayChange(Int($0.rounded())) }
                    ),
                    in: 0...20,
                    step: 1
                ) {
                    Text(L10n.tr("departures.walking.delay.slider"))
                } minimumValueLabel: {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("20")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityValue(L10n.tr("departures.walking.accessibility.value", departureDelayMinutes))
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

    private func delayPresetLabel(_ minutes: Int) -> String {
        if minutes == 0 {
            return L10n.tr("departures.walking.delay.preset.0")
        } else if minutes == 5 {
            return L10n.tr("departures.walking.delay.preset.5")
        } else {
            return L10n.tr("departures.walking.delay.preset.10")
        }
    }
}

// MARK: - Reliability Legend

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
