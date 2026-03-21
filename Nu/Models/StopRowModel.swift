import Foundation

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

        let planned = normalizeTimeToMinute(stop.depTime ?? stop.arrTime)
        let realtime = normalizeTimeToMinute(stop.rtDepTime ?? stop.rtArrTime)
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

    private static func normalizeTimeToMinute(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.contains(":"), clean.count >= 5 {
            return String(clean.prefix(5))
        }
        return clean
    }
}
