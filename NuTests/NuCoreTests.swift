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
}
