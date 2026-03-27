import Foundation
import CoreLocation

nonisolated final class WalkingETAService: WalkingETAServiceProtocol {
    nonisolated struct WalkLegMetric: Equatable {
        let durationSeconds: Int?
        let distanceMeters: Int?
    }

    typealias HafasWalkMetricsProvider = @Sendable (
        _ origin: CLLocationCoordinate2D,
        _ destination: WalkingETADestination
    ) async throws -> [WalkLegMetric]?

    nonisolated private struct CacheKey: Hashable {
        let destinationId: String
        let latBucket: Int
        let lonBucket: Int
        let timeBucket: Int

        init(destinationId: String, coordinate: CLLocationCoordinate2D, timestamp: Date) {
            self.destinationId = destinationId
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

    nonisolated private struct CacheEntry {
        let timestamp: Date
        let value: WalkETA
    }

    nonisolated private struct HafasWalkCandidate {
        let seconds: Int
        let distanceMeters: Int?
        let legCount: Int
        let selectedTripIdx: Int
        let usedField: String
    }

    private let client: HafasClient
    private let apiService: APIServiceProtocol
    private let mapKitService: MapKitWalkingETAServiceProtocol?
    private let clock: ClockProtocol
    private let overheadSeconds: Int
    private let hafasWalkMetricsProvider: HafasWalkMetricsProvider?
    private let cacheTTL: TimeInterval = 60
    private var cache: [CacheKey: CacheEntry] = [:]
    private let cacheLock = NSLock()

    init(
        client: HafasClient = HafasClient(),
        apiService: APIServiceProtocol,
        clock: ClockProtocol = SystemClock(),
        mapKitService: MapKitWalkingETAServiceProtocol? = nil,
        overheadSeconds: Int? = nil,
        hafasWalkMetricsProvider: HafasWalkMetricsProvider? = nil
    ) {
        self.client = client
        self.apiService = apiService
        self.clock = clock
        self.mapKitService = mapKitService
        self.overheadSeconds = max(0, overheadSeconds ?? AppConfig.walkETAOverheadSeconds)
        self.hafasWalkMetricsProvider = hafasWalkMetricsProvider
    }

    func fetchWalkETA(
        origin: CLLocationCoordinate2D,
        destination: WalkingETADestination,
        locationAccuracy: CLLocationAccuracy?,
        locationAgeSeconds: TimeInterval?
    ) async throws -> WalkETA {
        let key = CacheKey(destinationId: destination.stopId, coordinate: origin, timestamp: clock.now)

        if let cached = cachedValue(for: key), clock.now.timeIntervalSince(cached.timestamp) <= cacheTTL {
            let cachedValue = WalkETA(
                minutes: cached.value.minutes,
                baseMinutes: cached.value.baseMinutes,
                distanceMeters: cached.value.distanceMeters,
                source: cached.value.source
            )
            WalkETADebugLogger.log("cache=HIT destStopId=\(destination.stopId)")
            return cachedValue
        }

        let hafasCandidate = await fetchHafasCandidate(origin: origin, destination: destination)
        let mapKitResult = await fetchMapKitCandidate(origin: origin, destination: destination)
        let mapKitCandidate = mapKitResult.result
        let baseSeconds = max(hafasCandidate?.seconds ?? 0, mapKitCandidate?.expectedSeconds ?? 0)

        if baseSeconds > 0 {
            let routeDistance = max(hafasCandidate?.distanceMeters ?? 0, mapKitCandidate?.distanceMeters ?? 0)
            let model = applyConservativeModel(
                baseSeconds: baseSeconds,
                routeDistanceMeters: routeDistance > 0 ? routeDistance : nil,
                locationAccuracy: locationAccuracy
            )
            let minutes = max(1, Int(ceil(Double(model.finalSeconds) / 60.0)))
            let final = WalkETA(
                minutes: minutes,
                baseMinutes: Int(ceil(Double(baseSeconds) / 60.0)),
                distanceMeters: routeDistance > 0 ? routeDistance : nil,
                source: .hafasWalk
            )
            cacheValue(CacheEntry(timestamp: clock.now, value: final), for: key)
            logStructured(
                origin: origin,
                destination: destination,
                locationAccuracy: locationAccuracy,
                locationAgeSeconds: locationAgeSeconds,
                hafasCandidate: hafasCandidate,
                mapKitCandidate: mapKitCandidate,
                mapKitError: mapKitResult.errorText,
                model: model,
                finalSource: .hafasWalk,
                cacheStatus: "MISS"
            )
            return final
        }

        if let fallback = try await fetchFallback(origin: origin, destination: destination) {
            cacheValue(CacheEntry(timestamp: clock.now, value: fallback), for: key)
            logStructured(
                origin: origin,
                destination: destination,
                locationAccuracy: locationAccuracy,
                locationAgeSeconds: locationAgeSeconds,
                hafasCandidate: hafasCandidate,
                mapKitCandidate: mapKitCandidate,
                mapKitError: mapKitResult.errorText,
                model: nil,
                finalSource: .estimatedFallback,
                cacheStatus: "MISS"
            )
            return fallback
        }

        WalkETADebugLogger.log("failure reason=noHafasNoMapKitNoFallback")
        throw APIError.decodingFailed
    }

    private func fetchHafasCandidate(origin: CLLocationCoordinate2D, destination: WalkingETADestination) async -> HafasWalkCandidate? {
        if let hafasWalkMetricsProvider {
            do {
                guard let metrics = try await hafasWalkMetricsProvider(origin, destination),
                      let summary = Self.selectWalkingSummary(from: metrics)
                else {
                    WalkETADebugLogger.log("hafas failure reason=noInjectedWalkLeg")
                    return nil
                }

                return HafasWalkCandidate(
                    seconds: summary.totalDurationSeconds,
                    distanceMeters: summary.totalDistanceMeters,
                    legCount: metrics.count,
                    selectedTripIdx: 0,
                    usedField: summary.usedField
                )
            } catch {
                WalkETADebugLogger.log("hafas failure reason=injectedProvider detail=\(error.localizedDescription)")
                return nil
            }
        }

        var queryItems = [
            URLQueryItem(name: "originCoordLat", value: String(origin.latitude)),
            URLQueryItem(name: "originCoordLong", value: String(origin.longitude)),
            URLQueryItem(name: "destId", value: destination.stopId),
            URLQueryItem(name: "ivOnly", value: "1"),
            URLQueryItem(name: "totalWalk", value: "1"),
            URLQueryItem(name: "maxNo", value: "3")
        ]
        if let coord = destination.coordinate {
            queryItems.append(URLQueryItem(name: "destCoordLat", value: String(coord.latitude)))
            queryItems.append(URLQueryItem(name: "destCoordLong", value: String(coord.longitude)))
        }
        if let requestURL = try? client.makeURL(service: .trip, queryItems: queryItems) {
            WalkETADebugLogger.log("hafas request=\(requestURL.absoluteString)")
        }

        do {
            let response: HafasResponse<TripResponse> = try await client.request(
                service: .trip,
                queryItems: queryItems,
                context: HafasRequestContext(context: [
                    "feature": "walkETA",
                    "destStopId": destination.stopId
                ])
            )

            if response.value.trips.isEmpty {
                WalkETADebugLogger.log("hafas failure reason=tripListEmpty")
                return nil
            }

            var selectedTripIndex: Int?
            var selectedSummary: (totalDurationSeconds: Int, totalDistanceMeters: Int?, usedField: String)?
            var selectedLegCount = 0
            var totalWalkLegCount = 0

            for (index, trip) in response.value.trips.enumerated() {
                let walkLegs = trip.legs.filter { leg in
                    guard let type = leg.type?.uppercased() else { return false }
                    return type.contains("WALK") || type.contains("FOOT")
                }
                totalWalkLegCount += walkLegs.count
                for leg in walkLegs {
                    let durText = leg.durationSeconds.map(String.init) ?? "nil"
                    let distText = leg.distanceMeters.map(String.init) ?? "nil"
                    WalkETADebugLogger.log("hafas leg tripIdx=\(index) durS=\(durText) distM=\(distText) from=\(leg.originName ?? "?") to=\(leg.destinationName ?? "?")")
                }

                let metrics = walkLegs.map { WalkLegMetric(durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters) }
                if let summary = Self.selectWalkingSummary(from: metrics) {
                    selectedTripIndex = index
                    selectedSummary = summary
                    selectedLegCount = walkLegs.count
                    break
                }
            }

            guard let summary = selectedSummary, let selectedTripIndex else {
                WalkETADebugLogger.log("hafas failure reason=noWalkLeg tripCount=\(response.value.trips.count) walkLegCount=\(totalWalkLegCount)")
                return nil
            }

            return HafasWalkCandidate(
                seconds: summary.totalDurationSeconds,
                distanceMeters: summary.totalDistanceMeters,
                legCount: selectedLegCount,
                selectedTripIdx: selectedTripIndex,
                usedField: summary.usedField
            )
        } catch {
            if let apiError = error as? APIError {
                switch apiError {
                case .httpStatus(let status):
                    WalkETADebugLogger.log("hafas failure reason=httpStatus status=\(status)")
                case .decodingFailed:
                    WalkETADebugLogger.log("hafas failure reason=decodeError")
                case .serverMessage(let message):
                    WalkETADebugLogger.log("hafas failure reason=serverMessage detail=\(message)")
                case .network(let wrapped):
                    WalkETADebugLogger.log("hafas failure reason=network detail=\(wrapped.localizedDescription)")
                default:
                    WalkETADebugLogger.log("hafas failure reason=apiError detail=\(apiError.localizedDescription)")
                }
            } else {
                WalkETADebugLogger.log("hafas failure reason=requestError detail=\(error.localizedDescription)")
            }
            return nil
        }
    }

    private func fetchMapKitCandidate(
        origin: CLLocationCoordinate2D,
        destination: WalkingETADestination
    ) async -> (result: MapKitWalkingETAResult?, errorText: String?) {
        guard let destinationCoord = destination.coordinate else {
            return (nil, "missingDestinationCoord")
        }
        let service: MapKitWalkingETAServiceProtocol
        if let mapKitService {
            service = mapKitService
        } else {
            service = await MainActor.run { MapKitWalkingETAService() as MapKitWalkingETAServiceProtocol }
        }
        do {
            return (try await service.fetchWalkingETA(origin: origin, destination: destinationCoord), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func fetchFallback(origin: CLLocationCoordinate2D, destination: WalkingETADestination) async throws -> WalkETA? {
        let nearby = try await apiService.fetchNearbyStops(
            coordX: origin.longitude,
            coordY: origin.latitude,
            radiusMeters: 1_500,
            maxNo: 80
        )

        guard let station = nearby.first(where: { station in
            station.id == destination.stopId || station.extId == destination.stopId || station.globalId == destination.stopId
        }), let distance = station.distanceMeters else {
            WalkETADebugLogger.log("failure reason=noFallbackDistance")
            return nil
        }

        let conservativeMinutes = max(1, Int(ceil(distance / 1.1 / 60.0)))
        return WalkETA(
            minutes: conservativeMinutes,
            baseMinutes: nil,
            distanceMeters: Int(distance.rounded()),
            source: .estimatedFallback
        )
    }

    nonisolated static func selectWalkingSummary(from walkLegs: [WalkLegMetric]) -> (totalDurationSeconds: Int, totalDistanceMeters: Int?, usedField: String)? {
        let withDuration = walkLegs.compactMap { leg -> (Int, Int?, String)? in
            guard let duration = leg.durationSeconds, duration > 0 else { return nil }
            return (duration, leg.distanceMeters, "durS")
        }
        guard !withDuration.isEmpty else { return nil }

        let filtered = withDuration.filter { duration, distance, _ in
            if duration <= 30 { return false }
            if let distance, distance <= 20 { return false }
            return true
        }
        let candidates = filtered.isEmpty ? withDuration : filtered
        guard let selected = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        return (selected.0, selected.1, selected.2)
    }

    private func applyConservativeModel(
        baseSeconds: Int,
        routeDistanceMeters: Int?,
        locationAccuracy: CLLocationAccuracy?
    ) -> (
        baseSeconds: Int,
        gpsBufferSeconds: Int,
        intersectionBufferSeconds: Int,
        accPenaltySeconds: Int,
        multiplier: Double,
        finalSeconds: Int
    ) {
        let dist = routeDistanceMeters ?? 0
        let multiplier: Double
        if dist < 250 {
            multiplier = 1.20
        } else if dist < 600 {
            multiplier = 1.12
        } else {
            multiplier = 1.05
        }

        let accuracy = max(0, locationAccuracy ?? 0)
        let accPenalty = Int(ceil(max(0, accuracy - 20.0)))
        let intersectionBuffer = Int(ceil(Double(dist) / 250.0)) * 10
        let rawBuffer = overheadSeconds + intersectionBuffer + accPenalty
        let clampedBuffer = min(max(rawBuffer, 20), 90)
        let scaled = Int(ceil(Double(baseSeconds) * multiplier))
        let finalSeconds = max(baseSeconds, scaled + clampedBuffer)
        return (baseSeconds, clampedBuffer, intersectionBuffer, accPenalty, multiplier, finalSeconds)
    }

    private func logStructured(
        origin: CLLocationCoordinate2D,
        destination: WalkingETADestination,
        locationAccuracy: CLLocationAccuracy?,
        locationAgeSeconds: TimeInterval?,
        hafasCandidate: HafasWalkCandidate?,
        mapKitCandidate: MapKitWalkingETAResult?,
        mapKitError: String?,
        model: (
            baseSeconds: Int,
            gpsBufferSeconds: Int,
            intersectionBufferSeconds: Int,
            accPenaltySeconds: Int,
            multiplier: Double,
            finalSeconds: Int
        )?,
        finalSource: WalkETASource?,
        cacheStatus: String
    ) {
        let destSource: String
        if destination.coordinate != nil {
            destSource = "entrance"
        } else if !destination.stopId.isEmpty {
            destSource = "stop"
        } else {
            destSource = "fallback"
        }
        let destText: String
        if let coord = destination.coordinate {
            destText = "(\(coord.latitude),\(coord.longitude),source=\(destSource))"
        } else {
            destText = "nil"
        }

        let hafas = "hafas(durS=\(hafasCandidate?.seconds.description ?? "nil"),distM=\(hafasCandidate?.distanceMeters?.description ?? "nil"),legCount=\(hafasCandidate?.legCount ?? 0),used=\(hafasCandidate?.usedField ?? "none"))"
        let mapkit = "mapkit(expectedS=\(mapKitCandidate?.expectedSeconds.description ?? "nil"),distM=\(mapKitCandidate?.distanceMeters?.description ?? "nil"),used=\(mapKitCandidate != nil),err=\(mapKitError ?? (mapKitCandidate == nil ? "n/a" : "none")))"

        let modelText: String
        if let model {
            let finalMin = Int(ceil(Double(model.finalSeconds) / 60.0))
            modelText = "model(baseS=\(model.baseSeconds),bufferS=\(model.gpsBufferSeconds),intersectionS=\(model.intersectionBufferSeconds),accPenaltyS=\(model.accPenaltySeconds),multiplier=\(String(format: "%.2f", model.multiplier)),finalS=\(model.finalSeconds),finalMin=\(finalMin),mode=\(finalSource == .estimatedFallback ? "fallback" : "auto"))"
        } else {
            modelText = "model(baseS=nil,bufferS=nil,multiplier=nil,finalS=nil,finalMin=nil,mode=\(finalSource == .estimatedFallback ? "fallback" : "auto"))"
        }

        WalkETADebugLogger.log(
            "origin(\(origin.latitude),\(origin.longitude),accMeters=\(Int(locationAccuracy ?? -1)),timestamp=\(Int(locationAgeSeconds ?? -1))) " +
            "chosenMode=\(destination.mode.rawValue) destGroupId=\(destination.groupId ?? "nil"),chosenStopPointId=\(destination.stopId),dest=\(destText) " +
            "\(hafas) \(mapkit) \(modelText) cache=\(cacheStatus)"
        )
    }

    private func cacheKeyDescription(_ key: CacheKey) -> String {
        "dest=\(key.destinationId)|lat=\(key.latBucket)|lon=\(key.lonBucket)|tb=\(key.timeBucket)"
    }

    private func cachedValue(for key: CacheKey) -> CacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private func cacheValue(_ value: CacheEntry, for key: CacheKey) {
        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
    }
}

private struct TripResponse: Decodable {
    let trips: [TripItem]

    enum CodingKeys: String, CodingKey {
        case tripList = "TripList"
        case trip = "Trip"
    }

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated init(from decoder: Decoder) throws {
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

    nonisolated init(from decoder: Decoder) throws {
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
    nonisolated var distanceMeters: Int? { gisRoute?.dist ?? dist }

    enum CodingKeys: String, CodingKey {
        case type
        case gisRoute = "GisRoute"
        case dist
        case origin = "Origin"
        case destination = "Destination"
        case duration = "duration"
        case rtDuration = "rtDuration"
    }

    nonisolated init(from decoder: Decoder) throws {
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

    private nonisolated static func decodeDurationSeconds(
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

    private nonisolated static func parseDurationString(_ value: String) -> Int? {
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

    nonisolated init(from decoder: Decoder) throws {
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
