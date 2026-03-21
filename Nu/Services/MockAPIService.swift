import Foundation
import CoreLocation

/// Mock 服务：用于在未接入真实 API 时演示完整界面与交互。
///
/// 说明：
/// - 模拟网络延迟，便于观察加载态。
/// - 预置哥本哈根常见线路数据（5C、M3、RE）。
final class MockAPIService: APIServiceProtocol {
    func fetchDepartures(for stationID: String) async throws -> [Departure] {
        // 模拟网络耗时，让加载指示器可见。
        try await Task.sleep(nanoseconds: 500_000_000)

        return [
            Departure(
                name: "Bus 5C",
                type: "BUS",
                stop: "København H",
                time: "12:00",
                date: "11.02.26",
                rtTime: "12:02",
                rtDate: "11.02.26",
                direction: "Lufthavnen",
                finalStop: "Lufthavnen",
                track: "A",
                messages: nil
            ),
            Departure(
                name: "Metro M3",
                type: "METRO",
                stop: "København H",
                time: "12:05",
                date: "11.02.26",
                rtTime: "12:05",
                rtDate: "11.02.26",
                direction: "Cityringen",
                finalStop: "Cityringen",
                track: "M",
                messages: nil
            ),
            Departure(
                name: "Tog RE",
                type: "TOG",
                stop: "København H",
                time: "12:10",
                date: "11.02.26",
                rtTime: nil,
                rtDate: "11.02.26",
                direction: "Roskilde St.",
                finalStop: "Roskilde St.",
                track: "5",
                messages: "Sporarbejde"
            )
        ]
    }

    func fetchNearbyStops(
        coordX: Double,
        coordY: Double,
        radiusMeters: Int? = nil,
        maxNo: Int? = nil
    ) async throws -> [StationModel] {
        // 模拟一个较短网络延迟，便于看到加载态。
        try await Task.sleep(nanoseconds: 200_000_000)

        return [
            // TOG（红）— S-tog cls=8
            StationModel(
                id: "001",
                name: "København H",
                latitude: 55.672750,
                longitude: 12.565530,
                distanceMeters: 150,
                type: "ST",
                productsBitmask: 8
            ),
            // METRO（深蓝）— Metro cls=64
            StationModel(
                id: "002",
                name: "Rådhuspladsen (Metro)",
                latitude: 55.676130,
                longitude: 12.569290,
                distanceMeters: 420,
                type: "ST",
                productsBitmask: 64
            ),
            // BUS（黄）— Bus cls=16
            StationModel(
                id: "003",
                name: "Nørreport (Bus)",
                latitude: 55.683290,
                longitude: 12.571450,
                distanceMeters: 880,
                type: "ST",
                productsBitmask: 16
            )
        ]
    }

    func fetchDepartures(
        forStationIDs stationIDs: [String],
        maxJourneys: Int,
        filters: MultiDepartureFilters
    ) async throws -> [Departure] {
        let all = try await fetchDepartures(for: stationIDs.first ?? "mock")
        return Array(all.prefix(max(1, maxJourneys)))
    }

    func searchLocations(input: String) async throws -> [StationModel] {
        try await fetchNearbyStops(coordX: 12.568337, coordY: 55.676098, radiusMeters: nil, maxNo: nil)
            .filter { $0.name.localizedCaseInsensitiveContains(input.replacingOccurrences(of: "?", with: "")) }
    }

    func fetchJourneyDetail(id: String, date: String? = nil) async throws -> JourneyDetail {
        JourneyDetail(stops: [
            JourneyStop(id: "001", name: "København H", arrTime: "12:00", depTime: "12:02", track: "5"),
            JourneyStop(id: "002", name: "Nørreport", arrTime: "12:08", depTime: "12:09", track: "2")
        ])
    }

    func fetchJourneyPositions(
        bbox: JourneyPosBBox,
        filters: JourneyPosFilters,
        positionMode: JourneyPosMode
    ) async throws -> [JourneyVehicle] {
        let coordinate = CLLocationCoordinate2D(
            latitude: (bbox.llLat + bbox.urLat) / 2,
            longitude: (bbox.llLon + bbox.urLon) / 2
        )
        return [
            JourneyVehicle(
                id: filters.jid ?? "mock-vehicle-1",
                jid: filters.jid ?? "mock-vehicle-1",
                line: filters.lines.first ?? "5C",
                direction: "Lufthavnen",
                coordinate: coordinate,
                lastUpdated: Date(),
                isReportedPosition: true
            )
        ]
    }

    func resolveTrackingIdentity(from departure: Departure, operationDate: String?) async throws -> TrackingIdentity {
        TrackingIdentity(
            journeyRef: departure.journeyRef,
            jid: departure.journeyRef,
            line: departure.name,
            direction: departure.direction,
            plannedOrRealtimeDeparture: departure.effectiveDepartureDate?.date,
            matchConfidence: departure.journeyRef == nil ? .heuristic : .exact
        )
    }
}
