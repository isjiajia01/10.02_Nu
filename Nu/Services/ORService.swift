import Foundation

/// Operations Research service (pure computation, no UI dependency).
///
/// Responsibility: heuristic uncertainty-range estimation for departures.
/// All catch-probability / decision logic lives in `DecisionPolicy`.
struct ORService {
    struct HeuristicDistributionResult: Hashable {
        let uncertaintyRange: UncertaintyRange
        let reliabilityScore: Double
    }

    /// Compute heuristic uncertainty interval and initial reliability score.
    func heuristicDistribution(for departure: Departure) -> HeuristicDistributionResult {
        let hasRealtime = departure.rtTime != nil

        if hasRealtime {
            return HeuristicDistributionResult(
                uncertaintyRange: UncertaintyRange(lowerBound: -3.29, upperBound: 3.29),
                reliabilityScore: 0.82
            )
        } else {
            return HeuristicDistributionResult(
                uncertaintyRange: UncertaintyRange(lowerBound: 0.25, upperBound: 4.75),
                reliabilityScore: 0.55
            )
        }
    }

    /// Write heuristic results back into a new Departure value.
    func enrich(_ departure: Departure) -> Departure {
        let result = heuristicDistribution(for: departure)
        return Departure(
            journeyRef: departure.journeyRef,
            name: departure.name,
            type: departure.type,
            stop: departure.stop,
            time: departure.time,
            date: departure.date,
            rtTime: departure.rtTime,
            rtDate: departure.rtDate,
            direction: departure.direction,
            finalStop: departure.finalStop,
            track: departure.track,
            rtTrack: departure.rtTrack,
            messages: departure.messages,
            passListStops: departure.passListStops,
            uncertaintyRange: result.uncertaintyRange,
            reliabilityScore: result.reliabilityScore,
            catchProbability: departure.catchProbability,
            catchBucket: departure.catchBucket
        )
    }
}
