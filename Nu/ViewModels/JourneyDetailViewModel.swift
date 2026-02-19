import Foundation
import SwiftUI
import Combine

struct VehiclePositionInference: Equatable {
    enum Mode: Equatable {
        case between
        case atStop
        case unknown
    }

    let fromRealtime: Bool
    let fromStopIdx: Int?
    let toStopIdx: Int?
    let fromStopName: String?
    let toStopName: String?
    let mode: Mode

    static let unknown = VehiclePositionInference(
        fromRealtime: false,
        fromStopIdx: nil,
        toStopIdx: nil,
        fromStopName: nil,
        toStopName: nil,
        mode: .unknown
    )

    var estimatedBadgeText: String {
        fromRealtime ? L10n.tr("journeyDetail.estimated.rt") : L10n.tr("journeyDetail.estimated.sched")
    }

    var accessibilityLabel: String? {
        guard mode == .between, let fromStopName, let toStopName else { return nil }
        let source = fromRealtime ? L10n.tr("journeyDetail.estimated.source.realtime") : L10n.tr("journeyDetail.estimated.source.scheduled")
        return L10n.tr("journeyDetail.estimated.segment.a11y", fromStopName, toStopName, source)
    }
}

@MainActor
final class JourneyDetailViewModel: ObservableObject {
    let forceEagerRenderingForDebug = ProcessInfo.processInfo.environment["NU_JDETAIL_FORCE_EAGER"] == "1"

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rows: [StopRowModel] = []
    @Published var passedRows: [StopRowModel] = []
    @Published var upcomingRows: [StopRowModel] = []
    @Published var totalTravelSummaryText: String = L10n.tr("journeyDetail.destination.pending")
    @Published var currentIndex: Int?
    @Published var nextIndex: Int?
    @Published var currentOrNextIndex: Int?
    @Published var vehiclePositionInference: VehiclePositionInference = .unknown

    func load(
        journeyID: String,
        operationDate: String?,
        fallbackStops: [JourneyStop],
        currentStopName: String,
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
                currentStopName: currentStopName
            )
        } catch {
            if !fallbackStops.isEmpty {
                applyDerived(
                    journeyID: journeyID,
                    stops: fallbackStops,
                    operationDate: operationDate,
                    currentStopName: currentStopName
                )
            } else {
                let minimal = Self.buildMinimalStopsFromJourneyID(journeyID, currentStopName: currentStopName)
                if !minimal.isEmpty {
                    applyDerived(
                        journeyID: journeyID,
                        stops: minimal,
                        operationDate: operationDate,
                        currentStopName: currentStopName
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
        currentStopName: String
    ) {
        #if DEBUG
        Self.debugRawStopsDump(journeyID: journeyID, stops: stops)
        #endif
        rows = Self.buildDisplayRows(journeyID: journeyID, stops: stops)

        let displayable = rows.map(\.stop)

        let progress = JourneyProgressEstimator.infer(
            stops: displayable,
            fallbackCurrentStopName: currentStopName,
            operationDate: operationDate
        )
        currentIndex = progress.currentIndex
        nextIndex = progress.nextIndex
        currentOrNextIndex = progress.currentOrNextIndex
        totalTravelSummaryText = progress.minutesToDestination.map { L10n.tr("journeyDetail.destination.minutes", $0) } ?? L10n.tr("journeyDetail.destination.pending")
        vehiclePositionInference = Self.buildVehicleInference(progress: progress, stops: displayable)

        if let split = currentOrNextIndex, split > 0 {
            passedRows = Array(rows.prefix(split))
            upcomingRows = split < rows.count ? Array(rows.suffix(from: split)) : [rows.last].compactMap { $0 }
        } else {
            passedRows = []
            upcomingRows = rows
        }
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

    private static func buildVehicleInference(progress: JourneyProgressEstimation, stops: [JourneyStop]) -> VehiclePositionInference {
        switch progress.status {
        case .between(let from, let to):
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: progress.currentIndex,
                toStopIdx: progress.nextIndex,
                fromStopName: from,
                toStopName: to,
                mode: .between
            )
        case .at(let name):
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: progress.currentIndex,
                toStopIdx: nil,
                fromStopName: name,
                toStopName: nil,
                mode: .atStop
            )
        case .nearDestination:
            let idx = max(stops.count - 1, 0)
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: stops.isEmpty ? nil : idx,
                toStopIdx: nil,
                fromStopName: stops.last?.name,
                toStopName: nil,
                mode: .atStop
            )
        case .unknown:
            return .unknown
        }
    }

    private static func buildDisplayRows(journeyID: String, stops: [JourneyStop]) -> [StopRowModel] {
        var built: [StopRowModel] = []
        var activeZone: String?
        var previousZone: String?

        for stop in stops {
            let stopFieldZone = parseZoneFromStopField(stop)
            let zoneNodeZone = zoneLabel(from: stop)
            #if DEBUG
            if isZoneNode(stop) {
                let source = zoneLabelSource(from: stop)
                AppLogger.debug("[ZoneDebug][JourneyStop] name=\"\(stop.name)\" rawZone=\(stop.zone ?? "nil") parsed=\(zoneNodeZone ?? "nil") source=\(source)")
            }
            #endif

            if isZoneNode(stop) {
                if let zoneNodeZone {
                    activeZone = zoneNodeZone
                }
                continue
            }

            let effectiveZone = stopFieldZone ?? activeZone
            if let stopFieldZone { activeZone = stopFieldZone }

            let source: String
            if stopFieldZone != nil {
                source = "stop"
            } else if effectiveZone != nil {
                source = "gennemkzone"
            } else {
                source = "none"
            }

            #if DEBUG
            AppLogger.debug("[ZoneDebug] stopId=\(stop.id ?? "nil") name=\"\(stop.name)\" rawZone=\(stop.zone ?? "nil") inferredZone=\(effectiveZone ?? "nil") source=\(source)")
            #endif

            let zoneBadgeText: String?
            if let effectiveZone {
                if let previousZone, previousZone != effectiveZone {
                    zoneBadgeText = "Zone \(previousZone)→\(effectiveZone)"
                } else {
                    zoneBadgeText = "Zone \(effectiveZone)"
                }
            } else {
                zoneBadgeText = nil
            }
            previousZone = effectiveZone

            let row = StopRowModel.from(
                journeyID: journeyID,
                stop: stop,
                absoluteIndex: built.count,
                isTail: false,
                zoneBadgeText: zoneBadgeText,
                zoneCode: effectiveZone,
                zoneReason: source
            )
            built.append(row)
        }

        guard !built.isEmpty else { return [] }
        for idx in built.indices {
            built[idx] = built[idx].withTail(idx == built.count - 1)
        }
        #if DEBUG
        debugDisplayRowsDump(journeyID: journeyID, rows: built)
        #endif
        return built
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
        if lower.hasPrefix("gennemkzone") || lower.contains("takstzone") || lower.contains("tariff") {
            return true
        }
        let hasNoTimes = (stop.arrTime ?? stop.depTime ?? stop.rtArrTime ?? stop.rtDepTime) == nil
        return lower.contains("zone") && hasNoTimes
    }

    private static func isZoneNodeCandidate(_ stop: JourneyStop) -> Bool {
        let lower = stop.name.lowercased()
        return lower.contains("gennemkzone")
            || lower.contains("zone")
            || lower.contains("takstzone")
            || lower.contains("tariff")
    }

    private static func zoneLabel(from stop: JourneyStop) -> String? {
        guard isZoneNode(stop) else { return nil }

        if let explicitZone = normalizedZoneLabel(from: stop.zone) {
            return explicitZone
        }

        let lowerName = stop.name.lowercased()
        if let code = firstRegexMatch(pattern: #"gennemkzone\D*([0-9]{4,})"#, in: lowerName),
           let parsed = normalizedZoneFromGennemkzone(code) {
            return parsed
        }
        if let token = firstRegexMatch(pattern: #"zone\D*([0-9]{1,3})"#, in: lowerName),
           let parsed = normalizedZoneLabel(from: token) {
            return parsed
        }
        if let token = firstRegexMatch(pattern: #"([0-9]{1,3})"#, in: lowerName) {
            return normalizedZoneLabel(from: token)
        }
        return nil
    }

    private static func parseZoneFromStopField(_ stop: JourneyStop) -> String? {
        if let parsed = normalizedZoneLabel(from: stop.zone) {
            return parsed
        }
        if let parsed = normalizedZoneLabel(from: stop.tariffZone) {
            return parsed
        }
        if let list = stop.tariffZones {
            for value in list {
                if let parsed = normalizedZoneLabel(from: value) {
                    return parsed
                }
            }
        }
        for note in stop.notes ?? [] {
            let key = (note.key ?? "").uppercased()
            if key == "TN" || key == "TZ" || key == "ZONE" || key == "TARIFF" || key == "OZ" {
                if let parsed = normalizedZoneLabel(from: note.value) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static func zoneLabelSource(from stop: JourneyStop) -> String {
        guard isZoneNode(stop) else { return "notZoneNode" }
        if normalizedZoneLabel(from: stop.zone) != nil { return "stop.zone" }
        let lowerName = stop.name.lowercased()
        if let code = firstRegexMatch(pattern: #"gennemkzone\D*([0-9]{4,})"#, in: lowerName),
           normalizedZoneFromGennemkzone(code) != nil { return "name.gennemkzone" }
        if let token = firstRegexMatch(pattern: #"zone\D*([0-9]{1,3})"#, in: lowerName),
           normalizedZoneLabel(from: token) != nil { return "name.zoneToken" }
        if let token = firstRegexMatch(pattern: #"([0-9]{1,3})"#, in: lowerName),
           normalizedZoneLabel(from: token) != nil { return "name.digitsFallback" }
        return "missing"
    }

    private static func normalizedZoneFromGennemkzone(_ rawDigits: String) -> String? {
        let digits = rawDigits.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let suffix = String(digits.suffix(min(2, digits.count)))
        guard let value = Int(suffix), value > 0 else { return nil }
        return suffix.count == 1 ? String(value) : suffix
    }

    private static func normalizedZoneLabel(from raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let normalized: String
        if digits.count >= 2 {
            normalized = String(digits.suffix(2))
        } else {
            normalized = digits
        }
        guard let value = Int(normalized), value >= 1, value <= 99 else { return nil }
        return value < 10 ? String(format: "%02d", value) : String(format: "%02d", value)
    }

    #if DEBUG
    private static func debugRawStopsDump(journeyID: String, stops: [JourneyStop]) {
        AppLogger.debug("[ZoneDebug][RawDump] journeyId=\(journeyID) rawStopsCount=\(stops.count)")
        for (idx, stop) in stops.enumerated() {
            let hasTime = (stop.arrTime ?? stop.depTime ?? stop.rtArrTime ?? stop.rtDepTime) != nil
            let noteZones = (stop.notes ?? [])
                .filter { note in
                    let key = (note.key ?? "").uppercased()
                    return key == "TN" || key == "TZ" || key == "ZONE" || key == "TARIFF" || key == "OZ"
                }
                .compactMap(\.value)
            AppLogger.debug(
                "[ZoneDebug][RawStop] index=\(idx) id=\(stop.id ?? "nil") name=\"\(stop.name)\" type=\(stop.type ?? "nil") products=\(stop.products ?? "nil") hasArrDep=\(hasTime) zone=\(stop.zone ?? "nil") tariffZone=\(stop.tariffZone ?? "nil") tariffZones=\(stop.tariffZones?.joined(separator: ",") ?? "nil") noteZoneValues=\(noteZones.joined(separator: ",").isEmpty ? "nil" : noteZones.joined(separator: ",")) isZoneNodeCandidate=\(isZoneNodeCandidate(stop))"
            )
        }
    }

    private static func debugDisplayRowsDump(journeyID: String, rows: [StopRowModel]) {
        AppLogger.debug("[ZoneDebug][DisplayRows] journeyId=\(journeyID) rows=\(rows.count)")
        for (idx, row) in rows.enumerated() {
            AppLogger.debug(
                "[ZoneDebug][DisplayRow] index=\(idx) stopName=\"\(row.name)\" assignedZone=\(row.zoneCode ?? "nil") zoneBadgeText=\(row.zoneBadgeText ?? "nil") reason=\(row.zoneReason ?? "none")"
            )
        }
    }
    #endif

    private static func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard
            targetRange.location != NSNotFound,
            let swiftRange = Range(targetRange, in: text)
        else {
            return nil
        }
        return String(text[swiftRange])
    }
}

struct StopRowModel: Identifiable, Hashable {
    let id: String
    let stop: JourneyStop
    let absoluteIndex: Int
    let isTail: Bool
    let name: String
    let displayTime: String
    let isRealtime: Bool
    let trackText: String?
    let menuItems: [String]
    let zoneBadgeText: String?
    let zoneCode: String?
    let zoneReason: String?

    static func from(
        journeyID: String,
        stop: JourneyStop,
        absoluteIndex: Int,
        isTail: Bool,
        zoneBadgeText: String? = nil,
        zoneCode: String? = nil,
        zoneReason: String? = nil
    ) -> StopRowModel {
        let stableRouteIdx = stop.routeIdx ?? absoluteIndex
        let stableStopID = stop.id ?? "stop-\(absoluteIndex)"
        let id = "\(journeyID)-\(stableRouteIdx)-\(stableStopID)"

        let planned = JourneyDetailViewModel.normalizeTimeToMinute(stop.depTime ?? stop.arrTime)
        let realtime = JourneyDetailViewModel.normalizeTimeToMinute(stop.rtDepTime ?? stop.rtArrTime)
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
            stop: stop,
            absoluteIndex: absoluteIndex,
            isTail: isTail,
            name: stop.name,
            displayTime: displayTime,
            isRealtime: (stop.rtDepTime != nil || stop.rtArrTime != nil),
            trackText: trackText,
            menuItems: menuItems,
            zoneBadgeText: zoneBadgeText,
            zoneCode: zoneCode,
            zoneReason: zoneReason
        )
    }

    func withTail(_ tail: Bool) -> StopRowModel {
        StopRowModel(
            id: id,
            stop: stop,
            absoluteIndex: absoluteIndex,
            isTail: tail,
            name: name,
            displayTime: displayTime,
            isRealtime: isRealtime,
            trackText: trackText,
            menuItems: menuItems,
            zoneBadgeText: zoneBadgeText,
            zoneCode: zoneCode,
            zoneReason: zoneReason
        )
    }
}
