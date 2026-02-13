import XCTest
@testable import Nu

final class NuCoreTests: XCTestCase {
    func testJourneyDetailURLEncodingEncodesPipe() throws {
        let rawJourneyID = "2|#VN#1#ST#1770890916#"
        let encoded = HafasClient.encodeQueryValue(rawJourneyID)

        XCTAssertNotNil(encoded)
        XCTAssertTrue(encoded?.contains("%7C") == true, "Expected '|' to be encoded as %7C")
        XCTAssertFalse(encoded?.contains("|") == true, "Raw pipe must not appear in encoded query value")
    }

    func testStationGroupingMergesSameBaseNameWithinThreshold() {
        let a = StationModel(
            id: "1",
            name: "Nuuks Plads St. (Rantzausgade)",
            latitude: 55.68748,
            longitude: 12.54692,
            distanceMeters: 80,
            type: "BUS"
        )
        let b = StationModel(
            id: "2",
            name: "Nuuks Plads St. (Jagtvej)",
            latitude: 55.68760,
            longitude: 12.54680,
            distanceMeters: 110,
            type: "BUS"
        )

        let groups = StationGrouping.buildGroups([a, b], thresholdMeters: 250)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entranceCount, 2)
        XCTAssertEqual(groups[0].baseName, "Nuuks Plads St.")
    }

    func testORServiceHeuristicDistributionUsesRealtimeProfile() {
        let departure = Departure(
            name: "68",
            type: "BUS",
            stop: "Test",
            time: "23:59",
            date: "13.02.26",
            rtTime: "23:59",
            rtDate: "13.02.26",
            direction: "Bella Center",
            finalStop: "Bella Center",
            track: nil,
            messages: nil
        )
        let service = ORService()
        let result = service.heuristicDistribution(for: departure)

        XCTAssertEqual(result.uncertaintyRange.lowerBound, -3.29, accuracy: 0.001)
        XCTAssertEqual(result.uncertaintyRange.upperBound, 3.29, accuracy: 0.001)
        XCTAssertEqual(result.reliabilityScore, 0.82, accuracy: 0.001)
    }

    func testORServiceCatchProbabilityStates() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "dd.MM.yy"
        let today = formatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "da_DK")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        timeFormatter.dateFormat = "HH:mm"
        let departureTime = timeFormatter.string(from: Date().addingTimeInterval(6 * 60))

        let departure = Departure(
            name: "68",
            type: "BUS",
            stop: "Test",
            time: departureTime,
            date: today,
            rtTime: departureTime,
            rtDate: today,
            direction: "Bella Center",
            finalStop: "Bella Center",
            track: nil,
            messages: nil,
            uncertaintyRange: UncertaintyRange(lowerBound: 0, upperBound: 5),
            reliabilityScore: 0.7
        )
        let service = ORService()
        let base = Double(departure.minutesUntilDepartureRaw ?? 6)
        XCTAssertEqual(service.calculateCatchProbability(departure: departure, walkingMinutes: max(base - 2, 0)), .safe)
        XCTAssertEqual(service.calculateCatchProbability(departure: departure, walkingMinutes: base + 2), .risky)
        XCTAssertEqual(service.calculateCatchProbability(departure: departure, walkingMinutes: base + 6), .impossible)
    }

    func testJourneyProgressEstimatorInStopWindow() {
        let now = makeDate("2026-02-13 13:10")
        let stops: [JourneyStop] = [
            JourneyStop(id: "A", name: "Alpha", arrTime: nil, arrDate: nil, depTime: "13:00", depDate: "2026-02-13", track: nil),
            JourneyStop(id: "B", name: "Beta", arrTime: "13:08", arrDate: "2026-02-13", depTime: "13:12", depDate: "2026-02-13", track: nil),
            JourneyStop(id: "C", name: "Gamma", arrTime: "13:20", arrDate: "2026-02-13", depTime: "13:21", depDate: "2026-02-13", track: nil)
        ]

        let estimation = JourneyProgressEstimator.infer(
            stops: stops,
            fallbackCurrentStopName: "",
            operationDate: "2026-02-13",
            now: now
        )

        XCTAssertEqual(estimation.currentIndex, 1)
        XCTAssertEqual(estimation.nextIndex, 2)
        XCTAssertEqual(estimation.currentOrNextIndex, 1)
        XCTAssertEqual(estimation.minutesToDestination, 10)
        XCTAssertEqual(estimation.status, .between(from: "Beta", to: "Gamma"))
    }

    func testJourneyProgressEstimatorAfterDestination() {
        let now = makeDate("2026-02-13 14:00")
        let stops: [JourneyStop] = [
            JourneyStop(id: "A", name: "Alpha", arrTime: nil, arrDate: nil, depTime: "13:00", depDate: "2026-02-13", track: nil),
            JourneyStop(id: "B", name: "Beta", arrTime: "13:08", arrDate: "2026-02-13", depTime: "13:09", depDate: "2026-02-13", track: nil),
            JourneyStop(id: "C", name: "Gamma", arrTime: "13:20", arrDate: "2026-02-13", depTime: nil, depDate: nil, track: nil)
        ]

        let estimation = JourneyProgressEstimator.infer(
            stops: stops,
            fallbackCurrentStopName: "",
            operationDate: "2026-02-13",
            now: now
        )

        XCTAssertEqual(estimation.currentIndex, 2)
        XCTAssertNil(estimation.nextIndex)
        XCTAssertEqual(estimation.status, .nearDestination)
        XCTAssertEqual(estimation.minutesToDestination, 0)
    }

    private func makeDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
