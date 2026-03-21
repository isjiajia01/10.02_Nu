import Foundation

enum JourneyFallbackStopsBuilder {
    static func build(from rawJourneyID: String, currentStopName: String) -> [JourneyStop] {
        let tokens = rawJourneyID.split(separator: "#").map(String.init)

        func value(after key: String) -> String? {
            guard let index = tokens.firstIndex(of: key), index + 1 < tokens.count else {
                return nil
            }
            return tokens[index + 1]
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

        if fromID != nil && toID != nil {
            return [start, end]
        }

        return [fromID != nil ? start : end]
    }

    private static func normalizeTokenTime(_ token: String?) -> String? {
        guard let token, token.count == 4 else { return token }
        return "\(token.prefix(2)):\(token.suffix(2))"
    }
}
