import Foundation

enum JourneyDisplayRowBuilder {
    static func buildRows(journeyID: String, stops: [JourneyStop]) -> [StopRowModel] {
        var built: [StopRowModel] = []
        var activeZone: String?
        var previousZone: String?

        for stop in stops {
            let resolution = JourneyZoneParser.resolve(
                stop: stop,
                activeZone: activeZone,
                previousZone: previousZone
            )

            if resolution.source == "zoneNode" {
                if let zone = resolution.nextActiveZone {
                    backfillUnsetZones(in: &built, zoneCode: zone)
                    activeZone = zone
                }
                continue
            }

            let effectiveZone = resolution.effectiveZone
            let badgeText = makeBadgeText(
                previousZone: previousZone,
                effectiveZone: effectiveZone
            )

            let row = StopRowModel.from(
                journeyID: journeyID,
                stop: stop,
                absoluteIndex: built.count,
                isTail: false,
                zoneBadgeText: badgeText,
                zoneCode: effectiveZone,
                zoneReason: resolution.source
            )
            built.append(row)

            activeZone = resolution.nextActiveZone
            if let effectiveZone {
                previousZone = effectiveZone
            }
        }

        guard !built.isEmpty else { return [] }

        for index in built.indices {
            built[index] = built[index].withTail(index == built.count - 1)
        }

        #if DEBUG
        JourneyZoneParser.debugDisplayRowsDump(journeyID: journeyID, rows: built)
        #endif

        return built
    }

    private static func backfillUnsetZones(in rows: inout [StopRowModel], zoneCode: String) {
        let badgeText = makeBadgeText(previousZone: nil, effectiveZone: zoneCode)

        for index in rows.indices {
            guard rows[index].zoneCode == nil else { continue }
            rows[index] = copy(
                rows[index],
                zoneBadgeText: badgeText,
                zoneCode: zoneCode,
                zoneReason: "backfilledZoneNode"
            )
        }
    }

    private static func makeBadgeText(previousZone: String?, effectiveZone: String?) -> String? {
        guard let effectiveZone else { return nil }

        if let previousZone, previousZone != effectiveZone {
            return "Zone \(previousZone)→\(effectiveZone)"
        }

        return "Zone \(effectiveZone)"
    }

    private static func copy(
        _ row: StopRowModel,
        zoneBadgeText: String?,
        zoneCode: String?,
        zoneReason: String?
    ) -> StopRowModel {
        StopRowModel(
            id: row.id,
            stop: row.stop,
            absoluteIndex: row.absoluteIndex,
            isTail: row.isTail,
            name: row.name,
            displayTime: row.displayTime,
            isRealtime: row.isRealtime,
            trackText: row.trackText,
            menuItems: row.menuItems,
            zoneBadgeText: zoneBadgeText,
            zoneCode: zoneCode,
            zoneReason: zoneReason
        )
    }
}
