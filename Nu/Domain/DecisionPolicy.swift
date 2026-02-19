import Foundation

// MARK: - CatchBucket (replaces old CatchStatus)

/// Three-tier catch probability bucket for UI display.
/// Thresholds: Likely >= 0.85, Tight >= 0.40, Unlikely < 0.40.
enum CatchBucket: String, Codable, Hashable {
    case likely
    case tight
    case unlikely

    var label: String {
        switch self {
        case .likely:   return L10n.tr("catch.likely")
        case .tight:    return L10n.tr("catch.tight")
        case .unlikely: return L10n.tr("catch.unlikely")
        }
    }
}

// MARK: - ArriveDist

/// Distribution of user's estimated arrival at the platform (absolute Dates).
struct ArriveDist: Hashable {
    /// Optimistic arrival.
    let p10: Date
    /// Central estimate.
    let mean: Date
    /// Pessimistic arrival.
    let p90: Date
}

// MARK: - DecisionPolicy

/// Single source of truth for catch-probability decisions.
///
/// All comparisons use absolute `Date` values — never relative "minutes from
/// now" integers — to avoid truncation, drift, and scheduled/realtime mix-ups.
///
/// ViewModel calls these pure functions; View layer never computes
/// probability or branching logic directly.
enum DecisionPolicy {

    // MARK: - Arrive distribution

    /// Build the user's arrival-time distribution from walk ETA + departure delay.
    ///
    /// - Parameters:
    ///   - now: reference instant (injectable for testing).
    ///   - departureDelayMinutes: user-chosen "leave in N min" (0…20).
    ///   - walkMinutes: central walk-time estimate.
    ///   - walkP10: optimistic walk bound (minutes).
    ///   - walkP90: pessimistic walk bound (minutes).
    /// - Returns: `ArriveDist` with absolute `Date` values.
    static func computeArriveDistribution(
        now: Date = Date(),
        departureDelayMinutes: Int,
        walkMinutes: Double,
        walkP10: Double,
        walkP90: Double
    ) -> ArriveDist {
        let delay = Double(departureDelayMinutes) * 60  // seconds
        let lower = min(walkP10, walkP90) * 60
        let upper = max(walkP10, walkP90) * 60
        let center = walkMinutes * 60
        return ArriveDist(
            p10: now.addingTimeInterval(delay + lower),
            mean: now.addingTimeInterval(delay + center),
            p90: now.addingTimeInterval(delay + upper)
        )
    }

    // MARK: - Catch probability

    /// Compute the probability of catching a departure given the user's
    /// arrival distribution and the departure's effective time.
    ///
    /// Uses `departure.effectiveDepartureDate` (realtime-first) as the
    /// single source of truth for when the vehicle actually leaves.
    ///
    /// Returns `nil` when the departure date cannot be determined.
    static func computeCatchProbability(
        departure: Departure,
        arriveDist: ArriveDist
    ) -> Double? {
        guard let (depDate, _) = departure.effectiveDepartureDate else { return nil }

        // Departure uncertainty window (seconds)
        let lowerOffset = min(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound) * 60
        let upperOffset = max(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound) * 60

        let depEarliest = depDate.addingTimeInterval(lowerOffset)
        let depLatest   = depDate.addingTimeInterval(upperOffset)
        let depWidth    = max(depLatest.timeIntervalSince(depEarliest), 6) // at least 6s to avoid /0

        // Blend optimistic (p10) and pessimistic (p90) arrival
        let pAtP90 = probabilityFromArrival(arriveDist.p90, earliest: depEarliest, latest: depLatest, width: depWidth)
        let pAtP10 = probabilityFromArrival(arriveDist.p10, earliest: depEarliest, latest: depLatest, width: depWidth)

        return (pAtP10 + pAtP90) / 2.0
    }

    // MARK: - Bucket

    /// Map a raw probability to a three-tier bucket.
    static func bucket(_ probability: Double?) -> CatchBucket {
        guard let p = probability else { return .unlikely }
        if p >= 0.85 { return .likely }
        if p >= 0.40 { return .tight }
        return .unlikely
    }

    // MARK: - Probability formatting (single source of truth)

    /// Format a catch probability for display. All UI call sites must use this
    /// — never hand-build percentage strings in View or ViewModel.
    static func formatProbability(_ p: Double?) -> String {
        guard let p else { return "—" }
        let clamped = min(max(p, 0), 1)
        if clamped < 0.05 { return "<5%" }
        if clamped > 0.99 { return ">99%" }
        return "\(Int((clamped * 100).rounded()))%"
    }

    // MARK: - Convenience: enrich a Departure

    /// Compute catch probability + bucket and write them back into a new
    /// `Departure` value. This is the only call site ViewModel needs.
    static func enrichDecision(
        departure: Departure,
        now: Date = Date(),
        departureDelayMinutes: Int,
        walkMinutes: Double,
        walkP10: Double,
        walkP90: Double
    ) -> Departure {
        let arriveDist = computeArriveDistribution(
            now: now,
            departureDelayMinutes: departureDelayMinutes,
            walkMinutes: walkMinutes,
            walkP10: walkP10,
            walkP90: walkP90
        )
        let probability = computeCatchProbability(
            departure: departure,
            arriveDist: arriveDist
        )
        let catchBucket = bucket(probability)

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
            uncertaintyRange: departure.uncertaintyRange,
            reliabilityScore: departure.reliabilityScore,
            catchProbability: probability,
            catchBucket: catchBucket
        )
    }

    // MARK: - Private

    /// Given an arrival Date, compute the probability of arriving before
    /// the vehicle leaves, using the departure uncertainty window.
    private static func probabilityFromArrival(
        _ arrival: Date,
        earliest: Date,
        latest: Date,
        width: TimeInterval
    ) -> Double {
        if arrival <= earliest {
            return 0.97   // comfortably before the window
        }
        if arrival > latest {
            return 0.03   // after the window
        }
        // Linear interpolation within the window
        let remaining = latest.timeIntervalSince(arrival)
        return min(max(remaining / width, 0.05), 0.95)
    }
}
