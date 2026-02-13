import SwiftUI
import Combine

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

    @StateObject private var vm = JourneyDetailPageViewModel()
    @State private var showPassedStops = false
    @State private var showFullRoute = false

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
                    if vm.forceEagerRenderingForDebug {
                        VStack(spacing: 12) {
                            if let progressText = vm.progressStatus {
                                statusBanner(progressText)
                            }
                            if vm.hiddenZoneCount > 0 {
                                zoneBadge
                            }
                            scopeToggle
                            passedSection
                            timelineSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transaction { tx in
                            tx.disablesAnimations = true
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            if let progressText = vm.progressStatus {
                                statusBanner(progressText)
                            }
                            if vm.hiddenZoneCount > 0 {
                                zoneBadge
                            }
                            scopeToggle
                            passedSection
                            timelineSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transaction { tx in
                            tx.disablesAnimations = true
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("journeyDetail.title"))
        .navigationBarTitleDisplayMode(.inline)
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
            Text(L10n.tr("journeyDetail.summary.time", vm.startTimeSummary, vm.endTimeSummary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func statusBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
            Text(text)
                .font(.footnote.weight(.semibold))
            Spacer()
            Text(vm.positionEstimationLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.13))
        )
    }

    private var zoneBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
            Text(vm.zoneSummaryText)
                .font(.footnote.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
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

                // 折叠时完全不渲染 passed rows。
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
        HStack(alignment: .top, spacing: 10) {
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
                        .fill(visualState.lineColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 3)
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
                }
            }

            Spacer()

            if !row.menuItems.isEmpty {
                Menu {
                    ForEach(row.menuItems, id: \.self) { item in
                        Text(item)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(visualState.backgroundColor)
        )
    }

    private func load() async {
        await vm.load(
            journeyID: journeyID,
            operationDate: operationDate,
            fallbackStops: fallbackStops,
            currentStopName: currentStopName,
            plannedTime: plannedTime,
            realtimeTime: realtimeTime,
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
}

@MainActor
private final class JourneyDetailPageViewModel: ObservableObject {
    let forceEagerRenderingForDebug = ProcessInfo.processInfo.environment["NU_JDETAIL_FORCE_EAGER"] == "1"

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rows: [StopRowModel] = []
    @Published var passedRows: [StopRowModel] = []
    @Published var upcomingRows: [StopRowModel] = []
    @Published var hiddenZoneCount: Int = 0
    @Published var zoneSummaryText: String = ""
    @Published var progressStatus: String?
    @Published var positionEstimationLabel: String = L10n.tr("journeyDetail.position.scheduled")
    @Published var totalTravelSummaryText: String = L10n.tr("journeyDetail.destination.pending")
    @Published var startTimeSummary: String = "--:--"
    @Published var endTimeSummary: String = "--:--"
    @Published var currentIndex: Int?
    @Published var nextIndex: Int?
    @Published var currentOrNextIndex: Int?

    func load(
        journeyID: String,
        operationDate: String?,
        fallbackStops: [JourneyStop],
        currentStopName: String,
        plannedTime: String,
        realtimeTime: String?,
        apiService: APIServiceProtocol
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await apiService.fetchJourneyDetail(id: journeyID, date: operationDate)
            let baseStops: [JourneyStop]
            if detail.stops.isEmpty, !fallbackStops.isEmpty {
                baseStops = fallbackStops
            } else if detail.stops.isEmpty {
                baseStops = Self.buildMinimalStopsFromJourneyID(journeyID, currentStopName: currentStopName)
            } else {
                baseStops = detail.stops
            }
            applyDerived(
                journeyID: journeyID,
                stops: baseStops,
                operationDate: operationDate,
                currentStopName: currentStopName,
                plannedTime: plannedTime,
                realtimeTime: realtimeTime
            )
        } catch {
            if !fallbackStops.isEmpty {
                applyDerived(
                    journeyID: journeyID,
                    stops: fallbackStops,
                    operationDate: operationDate,
                    currentStopName: currentStopName,
                    plannedTime: plannedTime,
                    realtimeTime: realtimeTime
                )
            } else {
                let minimal = Self.buildMinimalStopsFromJourneyID(journeyID, currentStopName: currentStopName)
                if !minimal.isEmpty {
                    applyDerived(
                        journeyID: journeyID,
                        stops: minimal,
                        operationDate: operationDate,
                        currentStopName: currentStopName,
                        plannedTime: plannedTime,
                        realtimeTime: realtimeTime
                    )
                } else {
                    errorMessage = AppErrorPresenter.message(for: error, context: .journeyDetail)
                }
            }
        }

        isLoading = false
    }

    private func applyDerived(
        journeyID: String,
        stops: [JourneyStop],
        operationDate: String?,
        currentStopName: String,
        plannedTime: String,
        realtimeTime: String?
    ) {
        let displayable = stops.filter { !Self.isZoneNode($0) }
        rows = displayable.enumerated().map { index, stop in
            StopRowModel.from(
                journeyID: journeyID,
                stop: stop,
                absoluteIndex: index,
                isTail: index == displayable.count - 1
            )
        }

        hiddenZoneCount = max(0, stops.count - displayable.count)
        zoneSummaryText = Self.buildZoneSummaryText(stops: stops, hiddenCount: hiddenZoneCount)

        let progress = JourneyProgressEstimator.infer(
            stops: displayable,
            fallbackCurrentStopName: currentStopName,
            operationDate: operationDate
        )
        currentIndex = progress.currentIndex
        nextIndex = progress.nextIndex
        currentOrNextIndex = progress.currentOrNextIndex
        progressStatus = Self.localizedStatus(from: progress.status)
        positionEstimationLabel = progress.usesRealtime ? L10n.tr("journeyDetail.position.realtime") : L10n.tr("journeyDetail.position.scheduled")
        totalTravelSummaryText = progress.minutesToDestination.map { L10n.tr("journeyDetail.destination.minutes", $0) } ?? L10n.tr("journeyDetail.destination.pending")

        if let split = currentOrNextIndex, split > 0 {
            passedRows = Array(rows.prefix(split))
            upcomingRows = split < rows.count ? Array(rows.suffix(from: split)) : [rows.last].compactMap { $0 }
        } else {
            passedRows = []
            upcomingRows = rows
        }

        let first = displayable.first
        let last = displayable.last
        startTimeSummary = Self.buildStartTimeSummary(first: first, planned: plannedTime, realtime: realtimeTime)
        endTimeSummary = Self.buildEndTimeSummary(last: last)
    }

    private static func buildStartTimeSummary(first: JourneyStop?, planned: String, realtime: String?) -> String {
        let plannedStop = normalizeTimeToMinute(first?.depTime ?? planned)
        let realtimeStop = normalizeTimeToMinute(first?.rtDepTime ?? realtime)
        if let plannedStop, let realtimeStop, plannedStop != realtimeStop {
            return "\(plannedStop)→\(realtimeStop)"
        }
        return realtimeStop ?? plannedStop ?? "--:--"
    }

    private static func buildEndTimeSummary(last: JourneyStop?) -> String {
        let planned = normalizeTimeToMinute(last?.arrTime ?? last?.depTime)
        let realtime = normalizeTimeToMinute(last?.rtArrTime ?? last?.rtDepTime)
        if let planned, let realtime, planned != realtime {
            return "\(planned)→\(realtime)"
        }
        return realtime ?? planned ?? "--:--"
    }

    private static func buildZoneSummaryText(stops: [JourneyStop], hiddenCount: Int) -> String {
        let labels = Set(stops.compactMap(zoneLabel(from:)))
        if labels.isEmpty {
            return L10n.tr("journeyDetail.zone.hidden", hiddenCount)
        }
        return L10n.tr("journeyDetail.zone.summary", labels.sorted().joined(separator: " / "), hiddenCount)
    }

    private static func normalizeTokenTime(_ token: String?) -> String? {
        guard let token, token.count == 4 else { return token }
        return "\(token.prefix(2)):\(token.suffix(2))"
    }

    private static func buildMinimalStopsFromJourneyID(_ raw: String, currentStopName: String) -> [JourneyStop] {
        let tokens = raw.split(separator: "#").map(String.init)
        func value(after key: String) -> String? {
            guard let idx = tokens.firstIndex(of: key), idx + 1 < tokens.count else { return nil }
            return tokens[idx + 1]
        }

        let fromID = value(after: "FR")
        let fromTime = value(after: "FT")
        let toID = value(after: "TO")
        let toTime = value(after: "TT")

        guard fromID != nil || toID != nil else { return [] }

        let start = JourneyStop(
            id: fromID,
            name: currentStopName.isEmpty ? L10n.tr("journeyDetail.fallback.origin") : currentStopName,
            arrTime: nil,
            depTime: normalizeTokenTime(fromTime),
            track: nil
        )
        let end = JourneyStop(
            id: toID,
            name: L10n.tr("journeyDetail.fallback.destination"),
            arrTime: normalizeTokenTime(toTime),
            depTime: nil,
            track: nil
        )
        return (fromID != nil && toID != nil) ? [start, end] : [fromID != nil ? start : end]
    }

    private static func isZoneNode(_ stop: JourneyStop) -> Bool {
        let lower = stop.name.lowercased()
        if lower.hasPrefix("gennemkzone") { return true }
        let hasNoTimes = (stop.arrTime ?? stop.depTime ?? stop.rtArrTime ?? stop.rtDepTime) == nil
        return lower.contains("zone") && hasNoTimes
    }

    private static func zoneLabel(from stop: JourneyStop) -> String? {
        guard isZoneNode(stop) else { return nil }
        let digits = stop.name.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if digits.hasPrefix("0002") { return "2" }
        if digits.hasPrefix("0001") { return "1" }
        if let first = digits.first(where: { $0 != "0" }) { return String(first) }
        return nil
    }

    static func normalizeTimeToMinute(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.contains(":"), clean.count >= 5 {
            return String(clean.prefix(5))
        }
        return clean
    }

    private static func localizedStatus(from status: JourneyProgressEstimation.Status) -> String {
        switch status {
        case .between(let from, let to):
            return L10n.tr("journeyDetail.status.between", from, to)
        case .at(let name):
            return L10n.tr("journeyDetail.status.at", name)
        case .nearDestination:
            return L10n.tr("journeyDetail.status.nearDestination")
        case .unknown:
            return L10n.tr("journeyDetail.status.unknown")
        }
    }
}

private struct StopRowModel: Identifiable, Hashable {
    let id: String
    let absoluteIndex: Int
    let isTail: Bool
    let name: String
    let displayTime: String
    let isRealtime: Bool
    let trackText: String?
    let menuItems: [String]

    static func from(journeyID: String, stop: JourneyStop, absoluteIndex: Int, isTail: Bool) -> StopRowModel {
        let stableRouteIdx = stop.routeIdx ?? absoluteIndex
        let stableStopID = stop.id ?? "stop-\(absoluteIndex)"
        let id = "\(journeyID)-\(stableRouteIdx)-\(stableStopID)"

        let planned = JourneyDetailPageViewModel.normalizeTimeToMinute(stop.depTime ?? stop.arrTime)
        let realtime = JourneyDetailPageViewModel.normalizeTimeToMinute(stop.rtDepTime ?? stop.rtArrTime)
        let displayTime: String
        if let planned, let realtime, planned != realtime {
            displayTime = "\(planned) → \(realtime)"
        } else {
            displayTime = realtime ?? planned ?? "--:--"
        }

        let trackText: String?
        if let rtTrack = stop.rtTrack, let track = stop.track, rtTrack != track {
            trackText = L10n.tr("journeyDetail.track.changed", track, rtTrack)
        } else if let track = stop.rtTrack ?? stop.track {
            trackText = L10n.tr("journeyDetail.track", track)
        } else {
            trackText = nil
        }

        var menuItems: [String] = []
            if let sid = stop.id { menuItems.append(L10n.tr("journeyDetail.menu.id", sid)) }
            if let dep = stop.depTime { menuItems.append(L10n.tr("journeyDetail.menu.dep", dep)) }
            if let arr = stop.arrTime { menuItems.append(L10n.tr("journeyDetail.menu.arr", arr)) }
            if let rtDep = stop.rtDepTime { menuItems.append(L10n.tr("journeyDetail.menu.rtDep", rtDep)) }
            if let rtArr = stop.rtArrTime { menuItems.append(L10n.tr("journeyDetail.menu.rtArr", rtArr)) }

        return StopRowModel(
            id: id,
            absoluteIndex: absoluteIndex,
            isTail: isTail,
            name: stop.name,
            displayTime: displayTime,
            isRealtime: (stop.rtDepTime != nil || stop.rtArrTime != nil),
            trackText: trackText,
            menuItems: menuItems
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
