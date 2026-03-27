import Foundation
import CoreLocation
import MapKit

enum VehicleTrackingMatcher {
    struct SelectionContext {
        let identity: TrackingIdentity
        let currentMain: JourneyVehicle?
        let predictedCoordinate: CLLocationCoordinate2D?
        let originStopName: String
        let routeStops: [JourneyStop]
        let selectedStopCoordinate: CLLocationCoordinate2D?
    }

    struct SearchContext {
        let isBootstrap: Bool
        let forceGlobalReacquireRounds: Int
        let trackedVehicle: JourneyVehicle?
        let identity: TrackingIdentity
        let routeCoordinates: [CLLocationCoordinate2D]
        let visibleRegion: MKCoordinateRegion
        let localRadiusMeters: Double
        let originStopName: String
    }

    static func selectBestVehicle(
        from vehicles: [JourneyVehicle],
        context: SelectionContext
    ) -> JourneyVehicle? {
        guard !vehicles.isEmpty else { return nil }
        if let jid = context.identity.jid,
           let exact = vehicles.first(where: { $0.jid == jid || $0.id == jid }) {
            return exact
        }

        if let journeyRef = context.identity.journeyRef,
           let exactRef = vehicles.first(where: { $0.journeyDetailRef == journeyRef }) {
            return exactRef
        }

        let line = normalizedText(context.identity.line)
        let lineToken = normalizedLineToken(context.identity.line)
        let direction = normalizedText(context.identity.direction)
        let targetDate = context.identity.plannedOrRealtimeDeparture
        let normalizedOrigin = normalizedStopName(context.originStopName)
        let expectedIndex = expectedRouteStopIndex(in: context.routeStops, originStopName: context.originStopName)

        var candidates = filteredCandidates(
            from: vehicles,
            line: line,
            lineToken: lineToken,
            direction: direction,
            anchor: context.identity.lastKnownCoordinate
        )

        let scored = candidates.map { vehicle in
            score(
                vehicle: vehicle,
                line: line,
                lineToken: lineToken,
                direction: direction,
                normalizedOrigin: normalizedOrigin,
                expectedIndex: expectedIndex,
                targetDate: targetDate,
                context: context
            )
        }

        return scored.max(by: { $0.score < $1.score })?.vehicle
    }

    static func makeFetchBoxes(for context: SearchContext) -> [JourneyPosBBox] {
        if context.isBootstrap, !context.routeCoordinates.isEmpty {
            return routeBoundingBoxes(from: context.routeCoordinates)
        }
        if context.forceGlobalReacquireRounds > 0 {
            return JourneyPosBBox.from(
                center: context.visibleRegion.center,
                spanLatitude: context.visibleRegion.span.latitudeDelta,
                spanLongitude: context.visibleRegion.span.longitudeDelta
            )
        }
        if context.trackedVehicle == nil || context.identity.lastMatchedVehicleId == nil || routeSearchRequired(for: context) {
            return routeBoundingBoxes(from: context.routeCoordinates)
        }

        let center = context.identity.lastKnownCoordinate ?? context.trackedVehicle?.coordinate ?? context.visibleRegion.center
        let radius = max(400, min(context.localRadiusMeters, mapVisibleRadiusMeters(for: context.visibleRegion)))
        let latDelta = (radius * 2.0) / 111_000.0
        let lonScale = max(0.2, cos(center.latitude * .pi / 180))
        let lonDelta = (radius * 2.0) / (111_000.0 * lonScale)
        return JourneyPosBBox.from(center: center, spanLatitude: latDelta, spanLongitude: lonDelta)
    }

    static func routeBoundingBoxes(from routeCoordinates: [CLLocationCoordinate2D]) -> [JourneyPosBBox] {
        guard !routeCoordinates.isEmpty else { return [] }
        let latitudes = routeCoordinates.map(\.latitude)
        let longitudes = routeCoordinates.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return []
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let latSpan = max(0.08, (maxLat - minLat) * 1.4)
        let lonSpan = max(0.08, (maxLon - minLon) * 1.4)
        return JourneyPosBBox.from(center: center, spanLatitude: latSpan, spanLongitude: lonSpan)
    }

    static func normalizedStopName(_ text: String?) -> String {
        let base = normalizedText(text)
        guard !base.isEmpty else { return "" }
        let withoutParens = base.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        let ascii = withoutParens
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return ascii
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedLineToken(_ text: String?) -> String? {
        let raw = (text ?? "").lowercased()
        guard !raw.isEmpty else { return nil }
        let stripped = raw
            .replacingOccurrences(of: "bus", with: "")
            .replacingOccurrences(of: "metro", with: "")
            .replacingOccurrences(of: "tog", with: "")
            .replacingOccurrences(of: "line", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    static func expectedRouteStopIndex(in routeStops: [JourneyStop], originStopName: String) -> Int? {
        routeStopIndex(for: originStopName, in: routeStops)
    }

    private struct ScoredVehicle {
        let vehicle: JourneyVehicle
        let score: Double
    }

    private static func filteredCandidates(
        from vehicles: [JourneyVehicle],
        line: String,
        lineToken: String?,
        direction: String,
        anchor: CLLocationCoordinate2D?
    ) -> [JourneyVehicle] {
        var candidates = vehicles
        if let lineToken {
            let lineHits = vehicles.filter { normalizedLineToken($0.line) == lineToken }
            if !lineHits.isEmpty { candidates = lineHits }
        } else if !line.isEmpty {
            let lineHits = vehicles.filter { normalizedText($0.line) == line }
            if !lineHits.isEmpty { candidates = lineHits }
        }
        if !direction.isEmpty {
            let directionHits = candidates.filter { normalizedText($0.direction).contains(direction) }
            if !directionHits.isEmpty { candidates = directionHits }
        }
        if let anchor, candidates.count > 60 {
            candidates = candidates.sorted { lhs, rhs in
                let l = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
                    .distance(from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude))
                let r = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
                    .distance(from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude))
                return l < r
            }
            candidates = Array(candidates.prefix(60))
        }
        return candidates
    }

    private static func score(
        vehicle: JourneyVehicle,
        line: String,
        lineToken: String?,
        direction: String,
        normalizedOrigin: String,
        expectedIndex: Int?,
        targetDate: Date?,
        context: SelectionContext
    ) -> ScoredVehicle {
        var score = 0.0

        if let lineToken {
            if normalizedLineToken(vehicle.line) == lineToken { score += 5.5 }
        } else if normalizedText(vehicle.line) == line, !line.isEmpty {
            score += 4
        }

        if normalizedText(vehicle.direction).contains(direction), !direction.isEmpty {
            score += 2
        }

        if let currentStopName = context.identity.lastMatchedVehicleId == nil ? context.originStopName : nil,
           let stopName = vehicle.stopName,
           normalizedText(stopName).contains(normalizedText(currentStopName)) {
            score += 1.5
        }

        if let expectedIndex {
            let stopIndex = routeStopIndex(for: vehicle.stopName, in: context.routeStops)
            let nextStopIndex = routeStopIndex(for: vehicle.nextStopName, in: context.routeStops)

            if let stopIndex {
                let delta = abs(stopIndex - expectedIndex)
                score += max(0, 6 - Double(delta) * 1.5)
            }
            if let nextStopIndex {
                let segmentDelta = abs(nextStopIndex - expectedIndex)
                score += max(0, 5 - Double(segmentDelta) * 1.2)
            }
            if let stopIndex, let nextStopIndex, stopIndex <= expectedIndex, nextStopIndex >= expectedIndex {
                score += 4
            }
            if let stopIndex, stopIndex < expectedIndex - 3 {
                score -= Double(expectedIndex - stopIndex) * 0.8
            }
            if let nextStopIndex, nextStopIndex < expectedIndex - 2 {
                score -= Double(expectedIndex - nextStopIndex) * 1.2
            }
        } else if let stopName = vehicle.stopName, !normalizedOrigin.isEmpty,
                  normalizedStopName(stopName) == normalizedOrigin {
            score += 4
        }

        if let nextStopName = vehicle.nextStopName,
           !direction.isEmpty,
           normalizedText(nextStopName).contains(direction) {
            score += 1
        }

        if let targetDate, let t = vehicle.lastUpdated {
            score += max(0, 2 - abs(t.timeIntervalSince(targetDate)) / 60.0)
        }

        if let selectedStopCoordinate = context.selectedStopCoordinate {
            let distanceToSelectedStop = CLLocation(
                latitude: selectedStopCoordinate.latitude,
                longitude: selectedStopCoordinate.longitude
            ).distance(from: CLLocation(latitude: vehicle.coordinate.latitude, longitude: vehicle.coordinate.longitude))
            score += max(0, 8 - distanceToSelectedStop / 1000.0)
            if distanceToSelectedStop > 12_000 {
                score -= min(10, distanceToSelectedStop / 1500.0)
            }
        }

        if let predictedCoordinate = context.predictedCoordinate {
            let predictedDistance = CLLocation(latitude: predictedCoordinate.latitude, longitude: predictedCoordinate.longitude)
                .distance(from: CLLocation(latitude: vehicle.coordinate.latitude, longitude: vehicle.coordinate.longitude))
            score += max(0, 2 - predictedDistance / 500.0)
        }

        if let anchor = context.identity.lastKnownCoordinate {
            let distance = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: vehicle.coordinate.latitude, longitude: vehicle.coordinate.longitude))
            score += max(0, 3 - distance / 400.0)
        }

        if context.identity.lastMatchedVehicleId == vehicle.id {
            score += 2.5
        }
        if context.currentMain?.id == vehicle.id {
            score += 0.4
        }

        return ScoredVehicle(vehicle: vehicle, score: score)
    }

    private static func routeStopIndex(for candidate: String?, in routeStops: [JourneyStop]) -> Int? {
        let normalizedCandidate = normalizedStopName(candidate)
        guard !normalizedCandidate.isEmpty else { return nil }

        if let exact = routeStops.firstIndex(where: { normalizedStopName($0.name) == normalizedCandidate }) {
            return exact
        }
        if let exactPrefix = routeStops.firstIndex(where: {
            let normalizedRoute = normalizedStopName($0.name)
            return normalizedRoute.hasPrefix(normalizedCandidate) || normalizedCandidate.hasPrefix(normalizedRoute)
        }) {
            return exactPrefix
        }
        return routeStops.firstIndex {
            let normalizedRoute = normalizedStopName($0.name)
            return normalizedRoute.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedRoute)
        }
    }

    private static func routeSearchRequired(for context: SearchContext) -> Bool {
        let normalizedStop = normalizedStopName(context.originStopName)
        guard !normalizedStop.isEmpty else { return false }
        if let trackedVehicle = context.trackedVehicle,
           let stopName = trackedVehicle.stopName,
           normalizedStopName(stopName) == normalizedStop {
            return false
        }
        return true
    }

    private static func mapVisibleRadiusMeters(for region: MKCoordinateRegion) -> Double {
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let edge = CLLocation(
            latitude: region.center.latitude + region.span.latitudeDelta / 2.0,
            longitude: region.center.longitude
        )
        return max(500, center.distance(from: edge))
    }

    private static func normalizedText(_ text: String?) -> String {
        (text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
