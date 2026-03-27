import SwiftUI

struct JourneyDetailView: View {
    private let journeyID: String
    private let operationDate: String?
    private let fallbackStops: [JourneyStop]
    private let lineName: String
    private let transportType: String
    private let directionText: String
    private let currentStopName: String
    private let plannedTime: String
    private let realtimeTime: String?
    private let apiService: APIServiceProtocol

    @StateObject private var vm = JourneyDetailViewModel()
    @State private var showPassedStops = false
    @State private var showFullRoute = false
    @State private var showTrackingMap = false

    init(
        journeyID: String,
        operationDate: String? = nil,
        fallbackStops: [JourneyStop] = [],
        lineName: String = "",
        transportType: String = "",
        directionText: String = "",
        currentStopName: String = "",
        plannedTime: String = "",
        realtimeTime: String? = nil,
        apiService: APIServiceProtocol = RejseplanenAPIService()
    ) {
        self.journeyID = journeyID
        self.operationDate = operationDate
        self.fallbackStops = fallbackStops
        self.lineName = lineName
        self.transportType = transportType
        self.directionText = directionText
        self.currentStopName = currentStopName
        self.plannedTime = plannedTime
        self.realtimeTime = realtimeTime
        self.apiService = apiService
    }

    var body: some View {
        VStack(spacing: 0) {
            if !vm.rows.isEmpty {
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }

            if vm.isLoading {
                ProgressView(L10n.tr("journeyDetail.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = vm.errorMessage {
                ContentUnavailableView(L10n.tr("journeyDetail.loadFailed"), systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.rows.isEmpty {
                ContentUnavailableView(L10n.tr("journeyDetail.empty"), systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        if vm.forceEagerRenderingForDebug {
                            VStack(spacing: 12) {
                                scopeToggle
                                passedSection
                                timelineSection
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                scopeToggle
                                passedSection
                                timelineSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transaction { tx in
                        tx.disablesAnimations = true
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("journeyDetail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showTrackingMap) {
            VehicleTrackingMapView(
                departure: trackingDeparture,
                operationDate: operationDate,
                apiService: apiService
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showTrackingMap = true
                } label: {
                    Label(L10n.tr("journeyDetail.trackVehicle"), systemImage: "location.viewfinder")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .task {
            await load()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(transportType.isEmpty ? L10n.tr("journeyDetail.lineFallback") : transportType) \(lineName)")
                    .font(.headline.weight(.bold))
                Spacer()
                Text(vm.totalTravelSummaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.tr("journeyDetail.summary.direction", effectiveDirection))
                .font(.subheadline)
            Text(L10n.tr("journeyDetail.summary.route", routeStartName, routeEndName))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private var scopeToggle: some View {
        Picker(L10n.tr("journeyDetail.scope"), selection: $showFullRoute) {
            Text(L10n.tr("journeyDetail.scope.upcoming")).tag(false)
            Text(L10n.tr("journeyDetail.scope.full")).tag(true)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var passedSection: some View {
        if !showFullRoute && !vm.passedRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button(showPassedStops ? L10n.tr("journeyDetail.past.collapse", vm.passedRows.count) : L10n.tr("journeyDetail.past.expand", vm.passedRows.count)) {
                    showPassedStops.toggle()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

                if showPassedStops {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.passedRows) { row in
                            timelineRow(row: row, visualState: .passed, roleLabel: nil)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var timelineSection: some View {
        let rows = showFullRoute ? vm.rows : vm.upcomingRows
        return VStack(alignment: .leading, spacing: 10) {
            Text(showFullRoute ? L10n.tr("journeyDetail.stops.full") : L10n.tr("journeyDetail.stops.upcoming"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 10) {
                ForEach(rows) { row in
                    timelineRow(
                        row: row,
                        visualState: visualState(for: row.absoluteIndex),
                        roleLabel: roleLabel(for: row.absoluteIndex)
                    )
                }
            }
        }
    }

    private func timelineRow(row: StopRowModel, visualState: TimelineVisualState, roleLabel: String?) -> some View {
        let segmentHighlighted = isHighlightedSegmentStart(row.absoluteIndex)
        let segmentA11y = vm.vehiclePositionInference.accessibilityLabel

        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(visualState.dotColor)
                    .frame(width: visualState.dotSize, height: visualState.dotSize)
                    .overlay {
                        Circle()
                            .stroke(visualState.ringColor, lineWidth: visualState.ringWidth)
                    }
                    .padding(.top, 2)

                if !row.isTail {
                    Rectangle()
                        .fill(segmentHighlighted ? Color.accentColor : visualState.lineColor)
                        .frame(width: segmentHighlighted ? 4 : 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 3)
                        .accessibilityHidden(!segmentHighlighted)
                        .accessibilityLabel(segmentA11y ?? "")
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.body.weight(visualState == .current ? .bold : .semibold))
                    if let roleLabel {
                        Text(roleLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(visualState.badgeTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(visualState.badgeBackgroundColor)
                            .clipShape(Capsule())
                    }
                    if segmentHighlighted {
                        Text(vm.vehiclePositionInference.estimatedBadgeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(row.displayTime)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(visualState.timeColor)

                    Text(row.isRealtime ? L10n.tr("common.realtime") : L10n.tr("common.scheduled"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(row.isRealtime ? .green : .secondary)

                    if let track = row.trackText {
                        Text(track)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let zoneBadgeText = row.zoneBadgeText {
                        Text(zoneBadgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if !row.menuItems.isEmpty {
                Menu(L10n.tr("common.more"), systemImage: "ellipsis.circle") {
                    ForEach(row.menuItems, id: \.self) { item in
                        Text(item)
                    }
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(visualState.backgroundColor)
        )
        .overlay(alignment: .leading) {
            if let zoneCode = row.zoneCode {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(zoneColor(for: zoneCode).opacity(0.35))
                    .frame(width: 4)
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
            }
        }
    }

    private func load() async {
        await vm.load(
            journeyID: journeyID,
            operationDate: operationDate,
            fallbackStops: fallbackStops,
            currentStopName: currentStopName,
            apiService: apiService
        )
    }

    private var routeStartName: String {
        vm.rows.first?.name ?? currentStopName
    }

    private var routeEndName: String {
        vm.rows.last?.name ?? effectiveDirection
    }

    private var effectiveDirection: String {
        if !directionText.isEmpty { return directionText }
        return vm.rows.last?.name ?? "-"
    }

    private func visualState(for absoluteIndex: Int) -> TimelineVisualState {
        if vm.currentIndex == absoluteIndex { return .current }
        if vm.nextIndex == absoluteIndex { return .next }
        if let split = vm.currentOrNextIndex, absoluteIndex < split { return .passed }
        return .normal
    }

    private func roleLabel(for absoluteIndex: Int) -> String? {
        if vm.currentIndex == absoluteIndex { return L10n.tr("journeyDetail.role.current") }
        if vm.nextIndex == absoluteIndex { return L10n.tr("journeyDetail.role.next") }
        if absoluteIndex == 0 { return L10n.tr("journeyDetail.role.origin") }
        if absoluteIndex == vm.rows.count - 1 { return L10n.tr("journeyDetail.role.destination") }
        return nil
    }

    private func isHighlightedSegmentStart(_ absoluteIndex: Int) -> Bool {
        vm.vehiclePositionInference.mode == .between
            && vm.vehiclePositionInference.fromStopIdx == absoluteIndex
            && vm.vehiclePositionInference.toStopIdx == absoluteIndex + 1
    }

    private func zoneColor(for zoneCode: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in zoneCode.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
    }

    private var trackingDeparture: Departure {
        Departure(
            journeyRef: journeyID,
            name: lineName,
            type: transportType,
            stop: currentStopName,
            time: plannedTime,
            date: operationDate ?? "",
            rtTime: realtimeTime,
            rtDate: operationDate,
            direction: directionText,
            finalStop: directionText,
            track: nil,
            messages: nil
        )
    }
}

private enum TimelineVisualState: Equatable {
    case passed
    case normal
    case current
    case next

    var dotColor: Color {
        switch self {
        case .passed: return .gray.opacity(0.5)
        case .normal: return .gray.opacity(0.8)
        case .current: return .green
        case .next: return .blue
        }
    }

    var ringColor: Color {
        switch self {
        case .current: return .green.opacity(0.35)
        case .next: return .blue.opacity(0.35)
        case .passed, .normal: return .clear
        }
    }

    var ringWidth: CGFloat {
        switch self {
        case .current, .next: return 5
        case .passed, .normal: return 0
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .current, .next: return 12
        case .passed, .normal: return 10
        }
    }

    var lineColor: Color {
        switch self {
        case .passed: return .gray.opacity(0.35)
        case .normal: return .gray.opacity(0.25)
        case .current: return .green.opacity(0.45)
        case .next: return .blue.opacity(0.35)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .passed: return Color.gray.opacity(0.07)
        case .normal: return Color(.secondarySystemBackground)
        case .current: return Color.green.opacity(0.12)
        case .next: return Color.blue.opacity(0.10)
        }
    }

    var badgeBackgroundColor: Color {
        switch self {
        case .current: return Color.green.opacity(0.18)
        case .next: return Color.blue.opacity(0.18)
        case .passed, .normal: return Color.gray.opacity(0.12)
        }
    }

    var badgeTextColor: Color {
        switch self {
        case .current: return .green
        case .next: return .blue
        case .passed, .normal: return .secondary
        }
    }

    var timeColor: Color {
        switch self {
        case .current: return .green
        case .next: return .blue
        case .passed, .normal: return .secondary
        }
    }
}
