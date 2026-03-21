import Foundation

struct JourneyZoneResolution: Equatable {
    let effectiveZone: String?
    let nextActiveZone: String?
    let badgeText: String?
    let source: String
}

enum JourneyZoneParser {
    static func resolve(
        stop: JourneyStop,
        activeZone: String?,
        previousZone: String?
    ) -> JourneyZoneResolution {
        let stopFieldZone = parseZoneFromStopField(stop)
        let zoneNodeZone = zoneLabel(from: stop)

        #if DEBUG
        if isZoneNode(stop) {
            let source = zoneLabelSource(from: stop)
            AppLogger.debug("[ZoneDebug][JourneyStop] name=\"\(stop.name)\" rawZone=\(stop.zone ?? "nil") parsed=\(zoneNodeZone ?? "nil") source=\(source)")
        }
        #endif

        if isZoneNode(stop) {
            return JourneyZoneResolution(
                effectiveZone: nil,
                nextActiveZone: zoneNodeZone ?? activeZone,
                badgeText: nil,
                source: "zoneNode"
            )
        }

        let effectiveZone = stopFieldZone ?? activeZone
        let nextActiveZone = stopFieldZone ?? activeZone

        let source: String
        if stopFieldZone != nil {
            source = "stop"
        } else if effectiveZone != nil {
            source = "gennemkzone"
        } else {
            source = "none"
        }

        let badgeText: String?
        if let effectiveZone {
            let currentDisplayZone = displayZoneBadgeValue(from: effectiveZone)
            if let previousZone, previousZone != effectiveZone {
                let previousDisplayZone = displayZoneBadgeValue(from: previousZone)
                badgeText = "Zone \(previousDisplayZone)→\(currentDisplayZone)"
            } else {
                badgeText = "Zone \(currentDisplayZone)"
            }
        } else {
            badgeText = nil
        }

        #if DEBUG
        AppLogger.debug("[ZoneDebug] stopId=\(stop.id ?? "nil") name=\"\(stop.name)\" rawZone=\(stop.zone ?? "nil") inferredZone=\(effectiveZone ?? "nil") source=\(source)")
        #endif

        return JourneyZoneResolution(
            effectiveZone: effectiveZone,
            nextActiveZone: nextActiveZone,
            badgeText: badgeText,
            source: source
        )
    }

    static func isZoneNode(_ stop: JourneyStop) -> Bool {
        let lower = stop.name.lowercased()
        if lower.hasPrefix("gennemkzone") || lower.contains("takstzone") || lower.contains("tariff") {
            return true
        }

        let hasNoTimes = (stop.arrTime ?? stop.depTime ?? stop.rtArrTime ?? stop.rtDepTime) == nil
        return lower.contains("zone") && hasNoTimes
    }

    static func isZoneNodeCandidate(_ stop: JourneyStop) -> Bool {
        let lower = stop.name.lowercased()
        return lower.contains("gennemkzone")
            || lower.contains("zone")
            || lower.contains("takstzone")
            || lower.contains("tariff")
    }

    static func zoneLabel(from stop: JourneyStop) -> String? {
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

    static func parseZoneFromStopField(_ stop: JourneyStop) -> String? {
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

    static func zoneLabelSource(from stop: JourneyStop) -> String {
        guard isZoneNode(stop) else { return "notZoneNode" }
        if normalizedZoneLabel(from: stop.zone) != nil { return "stop.zone" }

        let lowerName = stop.name.lowercased()
        if let code = firstRegexMatch(pattern: #"gennemkzone\D*([0-9]{4,})"#, in: lowerName),
           normalizedZoneFromGennemkzone(code) != nil {
            return "name.gennemkzone"
        }
        if let token = firstRegexMatch(pattern: #"zone\D*([0-9]{1,3})"#, in: lowerName),
           normalizedZoneLabel(from: token) != nil {
            return "name.zoneToken"
        }
        if let token = firstRegexMatch(pattern: #"([0-9]{1,3})"#, in: lowerName),
           normalizedZoneLabel(from: token) != nil {
            return "name.digitsFallback"
        }
        return "missing"
    }

    static func normalizedZoneFromGennemkzone(_ rawDigits: String) -> String? {
        let digits = rawDigits.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        let suffix = String(digits.suffix(min(2, digits.count)))
        guard let value = Int(suffix), value > 0 else { return nil }

        return suffix.count == 1 ? String(value) : suffix
    }

    static func normalizedZoneLabel(from raw: String?) -> String? {
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
        return String(format: "%02d", value)
    }

    static func displayZoneBadgeValue(from normalizedZone: String) -> String {
        if let value = Int(normalizedZone) {
            return String(value)
        }
        return normalizedZone
    }

    #if DEBUG
    static func debugRawStopsDump(journeyID: String, stops: [JourneyStop]) {
        AppLogger.debug("[ZoneDebug][RawDump] journeyId=\(journeyID) rawStopsCount=\(stops.count)")
        for (idx, stop) in stops.enumerated() {
            let hasTime = (stop.arrTime ?? stop.depTime ?? stop.rtArrTime ?? stop.rtDepTime) != nil
            let noteZones = (stop.notes ?? [])
                .filter { note in
                    let key = (note.key ?? "").uppercased()
                    return key == "TN" || key == "TZ" || key == "ZONE" || key == "TARIFF" || key == "OZ"
                }
                .compactMap(\.value)

            let noteZoneText = noteZones.joined(separator: ",")
            AppLogger.debug(
                "[ZoneDebug][RawStop] index=\(idx) id=\(stop.id ?? "nil") name=\"\(stop.name)\" type=\(stop.type ?? "nil") products=\(stop.products ?? "nil") hasArrDep=\(hasTime) zone=\(stop.zone ?? "nil") tariffZone=\(stop.tariffZone ?? "nil") tariffZones=\(stop.tariffZones?.joined(separator: ",") ?? "nil") noteZoneValues=\(noteZoneText.isEmpty ? "nil" : noteZoneText) isZoneNodeCandidate=\(isZoneNodeCandidate(stop))"
            )
        }
    }

    static func debugDisplayRowsDump(journeyID: String, rows: [StopRowModel]) {
        AppLogger.debug("[ZoneDebug][DisplayRows] journeyId=\(journeyID) rows=\(rows.count)")
        for (idx, row) in rows.enumerated() {
            AppLogger.debug(
                "[ZoneDebug][DisplayRow] index=\(idx) stopName=\"\(row.name)\" assignedZone=\(row.zoneCode ?? "nil") zoneBadgeText=\(row.zoneBadgeText ?? "nil") reason=\(row.zoneReason ?? "none")"
            )
        }
    }
    #endif

    static func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        guard targetRange.location != NSNotFound,
              let swiftRange = Range(targetRange, in: text) else {
            return nil
        }

        return String(text[swiftRange])
    }
}
