import Foundation
import CoreLocation

actor WalkingETAService: WalkingETAServiceProtocol {
    struct WalkLegMetric: Equatable {
        let durationSeconds: Int?
        let distanceMeters: Int?
    }

    private struct CacheKey: Hashable {
        let destStopId: String
        let latBucket: Int
        let lonBucket: Int
        let timeBucket: Int

        init(destStopId: String, coordinate: CLLocationCoordinate2D, timestamp: Date) {
            self.destStopId = destStopId
            let rounded = Self.roundedCoordinate(coordinate)
            self.latBucket = Int((rounded.latitude * 100_000).rounded())
            self.lonBucket = Int((rounded.longitude * 100_000).rounded())
            self.timeBucket = Int(timestamp.timeIntervalSince1970 / 30.0)
        }

        private static func roundedCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
            let latStep = 50.0 / 111_000.0
            let cosLat = max(cos(coordinate.latitude * .pi / 180.0), 0.2)
            let lonStep = 50.0 / (111_000.0 * cosLat)
            let lat = (coordinate.latitude / latStep).rounded() * latStep
            let lon = (coordinate.longitude / lonStep).rounded() * lonStep
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private struct CacheEntry {
        let timestamp: Date
        let value: WalkETA
    }

    private let client: HafasClient
    private let apiService: APIServiceProtocol
    private let clock: ClockProtocol
    private let cacheTTL: TimeInterval = 60
    private var cache: [CacheKey: CacheEntry] = [:]

    init(
        client: HafasClient = HafasClient(),
        apiService: APIServiceProtocol,
        clock: ClockProtocol = SystemClock()
    ) {
        self.client = client
        self.apiService = apiService
        self.clock = clock
    }

    func fetchWalkETA(origin: CLLocationCoordinate2D, destStopId: String) async throws -> WalkETA {
        let key = CacheKey(destStopId: destStopId, coordinate: origin, timestamp: clock.now)
        log("[WalkETA] origin=(\(origin.latitude),\(origin.longitude)) dest=\(destStopId)")

        if let cached = cache[key], clock.now.timeIntervalSince(cached.timestamp) <= cacheTTL {
            log("[WalkETA][cache] HIT key=\(cacheKeyDescription(key)) minutes=\(cached.value.minutes) source=\(cached.value.source)")
            return cached.value
        }
        log("[WalkETA][cache] MISS key=\(cacheKeyDescription(key))")

        do {
            let walkETA = try await fetchFromTrip(origin: origin, destStopId: destStopId)
            cache[key] = CacheEntry(timestamp: clock.now, value: walkETA)
            log("[WalkETA] source=\(walkETA.source) cache=MISS minutes=\(walkETA.minutes)")
            return walkETA
        } catch {
            if let fallback = try await fetchFallback(origin: origin, destStopId: destStopId) {
                cache[key] = CacheEntry(timestamp: clock.now, value: fallback)
                log("[WalkETA] source=\(fallback.source) cache=MISS minutes=\(fallback.minutes)")
                return fallback
            }
            throw error
        }
    }

    private func fetchFromTrip(origin: CLLocationCoordinate2D, destStopId: String) async throws -> WalkETA {
        let response: HafasResponse<TripResponse> = try await client.request(
            service: .trip,
            queryItems: [
                URLQueryItem(name: "originCoordLat", value: String(origin.latitude)),
                URLQueryItem(name: "originCoordLong", value: String(origin.longitude)),
                URLQueryItem(name: "destId", value: destStopId),
                URLQueryItem(name: "ivOnly", value: "1"),
                URLQueryItem(name: "totalWalk", value: "1"),
                URLQueryItem(name: "maxNo", value: "1")
            ],
            context: HafasRequestContext(context: [
                "feature": "walkETA",
                "destStopId": destStopId
            ])
        )
        if let requestURL = try? client.makeURL(service: .trip, queryItems: [
            URLQueryItem(name: "originCoordLat", value: String(origin.latitude)),
            URLQueryItem(name: "originCoordLong", value: String(origin.longitude)),
            URLQueryItem(name: "destId", value: destStopId),
            URLQueryItem(name: "ivOnly", value: "1"),
            URLQueryItem(name: "totalWalk", value: "1"),
            URLQueryItem(name: "maxNo", value: "1")
        ]) {
            log("[WalkETA] request=\(requestURL.absoluteString)")
        }

        guard let trip = response.value.trips.first else {
            throw APIError.decodingFailed
        }

        let walkLegs = trip.legs.filter { leg in
            guard let type = leg.type?.uppercased() else { return false }
            return type.contains("WALK") || type.contains("FOOT")
        }
        log("[WalkETA] legs:")
        for leg in walkLegs {
            let durText = leg.durationSeconds.map(String.init) ?? "nil"
            let distText = leg.distanceMeters.map(String.init) ?? "nil"
            log("  - \(leg.type ?? "nil") durS=\(durText) dist=\(distText) from=\(leg.originName ?? "?") to=\(leg.destinationName ?? "?")")
        }

        guard !walkLegs.isEmpty else {
            throw APIError.decodingFailed
        }

        let metrics = walkLegs.map { WalkLegMetric(durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters) }
        guard let summary = Self.selectWalkingSummary(from: metrics) else {
            throw APIError.decodingFailed
        }

        let minutes = max(1, Int(ceil(Double(summary.totalDurationSeconds) / 60.0)))
        log("[WalkETA] chosenDurS=\(summary.totalDurationSeconds) chosenDist=\(summary.totalDistanceMeters?.description ?? "nil") => minutes=\(minutes)")

        return WalkETA(
            minutes: minutes,
            distanceMeters: summary.totalDistanceMeters,
            source: .hafasWalk
        )
    }

    private func fetchFallback(origin: CLLocationCoordinate2D, destStopId: String) async throws -> WalkETA? {
        let nearby = try await apiService.fetchNearbyStops(
            coordX: origin.longitude,
            coordY: origin.latitude,
            radiusMeters: 1_500,
            maxNo: 80
        )

        guard let station = nearby.first(where: { station in
            station.id == destStopId || station.extId == destStopId || station.globalId == destStopId
        }), let distance = station.distanceMeters else {
            return nil
        }

        let minutes = max(1, Int(ceil(distance / 1.3 / 60.0)))

        return WalkETA(
            minutes: minutes,
            distanceMeters: Int(distance.rounded()),
            source: .estimatedFallback
        )
    }

    static func selectWalkingSummary(from walkLegs: [WalkLegMetric]) -> (totalDurationSeconds: Int, totalDistanceMeters: Int?)? {
        let withDuration = walkLegs.compactMap { leg -> (Int, Int?)? in
            guard let duration = leg.durationSeconds, duration > 0 else { return nil }
            return (duration, leg.distanceMeters)
        }
        guard !withDuration.isEmpty else { return nil }

        let totalDuration = withDuration.reduce(0) { $0 + $1.0 }
        let totalDistance = withDuration.compactMap(\.1).reduce(0, +)
        return (totalDuration, totalDistance > 0 ? totalDistance : nil)
    }

    private func cacheKeyDescription(_ key: CacheKey) -> String {
        "dest=\(key.destStopId)|lat=\(key.latBucket)|lon=\(key.lonBucket)|tb=\(key.timeBucket)"
    }

    private func log(_ message: String) {
        #if DEBUG
        fputs("\(message)\n", stderr)
        #endif
    }
}

private struct TripResponse: Decodable {
    let trips: [TripItem]

    enum CodingKeys: String, CodingKey {
        case tripList = "TripList"
        case trip = "Trip"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let list = try? container.decode(TripListContainer.self, forKey: .tripList) {
            trips = list.trips
            return
        }

        if let direct = try? container.decode([TripItem].self, forKey: .trip) {
            trips = direct
            return
        }
        if let single = try? container.decode(TripItem.self, forKey: .trip) {
            trips = [single]
            return
        }

        trips = []
    }
}

private struct TripListContainer: Decodable {
    let trips: [TripItem]

    enum CodingKeys: String, CodingKey {
        case trip = "Trip"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([TripItem].self, forKey: .trip) {
            trips = list
        } else if let single = try? container.decode(TripItem.self, forKey: .trip) {
            trips = [single]
        } else {
            trips = []
        }
    }
}

private struct TripItem: Decodable {
    let legs: [TripLeg]

    enum CodingKeys: String, CodingKey {
        case legList = "LegList"
        case leg = "Leg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let legList = try? container.decode(LegListContainer.self, forKey: .legList) {
            legs = legList.legs
            return
        }

        if let list = try? container.decode([TripLeg].self, forKey: .leg) {
            legs = list
            return
        }

        if let single = try? container.decode(TripLeg.self, forKey: .leg) {
            legs = [single]
            return
        }

        legs = []
    }
}

private struct LegListContainer: Decodable {
    let legs: [TripLeg]

    enum CodingKeys: String, CodingKey {
        case leg = "Leg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([TripLeg].self, forKey: .leg) {
            legs = list
        } else if let single = try? container.decode(TripLeg.self, forKey: .leg) {
            legs = [single]
        } else {
            legs = []
        }
    }
}

private struct TripLeg: Decodable {
    let type: String?
    let gisRoute: GisRoute?
    let dist: Int?
    let originName: String?
    let destinationName: String?
    let durationSeconds: Int?
    var distanceMeters: Int? { gisRoute?.dist ?? dist }

    enum CodingKeys: String, CodingKey {
        case type
        case gisRoute = "GisRoute"
        case dist
        case origin = "Origin"
        case destination = "Destination"
        case duration = "duration"
        case rtDuration = "rtDuration"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decode(String.self, forKey: .type)
        gisRoute = try? container.decode(GisRoute.self, forKey: .gisRoute)
        originName = (try? container.decode(TripLegPoint.self, forKey: .origin))?.name
        destinationName = (try? container.decode(TripLegPoint.self, forKey: .destination))?.name
        durationSeconds =
            Self.decodeDurationSeconds(container: container, key: .rtDuration)
            ?? Self.decodeDurationSeconds(container: container, key: .duration)
            ?? gisRoute?.durS

        if let value = try? container.decode(Int.self, forKey: .dist) {
            dist = value
        } else if let value = try? container.decode(Double.self, forKey: .dist) {
            dist = Int(value.rounded())
        } else if let value = try? container.decode(String.self, forKey: .dist), let parsed = Int(value) {
            dist = parsed
        } else {
            dist = nil
        }
    }

    private static func decodeDurationSeconds(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let intVal = try? container.decode(Int.self, forKey: key) {
            return intVal
        }
        if let strVal = try? container.decode(String.self, forKey: key) {
            return parseDurationString(strVal)
        }
        return nil
    }

    private static func parseDurationString(_ value: String) -> Int? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        if let raw = Int(clean) {
            return raw
        }
        let parts = clean.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return nil
    }
}

private struct TripLegPoint: Decodable {
    let name: String?

    enum CodingKeys: String, CodingKey {
        case name
    }
}

private struct GisRoute: Decodable {
    let durS: Int?
    let dist: Int?

    enum CodingKeys: String, CodingKey {
        case durS
        case dist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode(Int.self, forKey: .durS) {
            durS = value
        } else if let value = try? container.decode(Double.self, forKey: .durS) {
            durS = Int(value.rounded())
        } else if let value = try? container.decode(String.self, forKey: .durS), let parsed = Int(value) {
            durS = parsed
        } else {
            durS = nil
        }

        if let value = try? container.decode(Int.self, forKey: .dist) {
            dist = value
        } else if let value = try? container.decode(Double.self, forKey: .dist) {
            dist = Int(value.rounded())
        } else if let value = try? container.decode(String.self, forKey: .dist), let parsed = Int(value) {
            dist = parsed
        } else {
            dist = nil
        }
    }
}
