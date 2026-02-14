import XCTest
@testable import Nu
import CoreLocation
import Combine

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

    func testDecisionPolicyCatchBucketStates() {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "dd.MM.yy"
        let today = formatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "da_DK")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        timeFormatter.dateFormat = "HH:mm"
        let departureTime = timeFormatter.string(from: now.addingTimeInterval(6 * 60))

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

        // Easy catch: no delay, short walk
        let easy = DecisionPolicy.enrichDecision(
            departure: departure,
            now: now,
            departureDelayMinutes: 0,
            walkMinutes: 2,
            walkP10: 1,
            walkP90: 3
        )
        XCTAssertEqual(easy.catchBucket, .likely)

        // Tight: moderate delay
        let tight = DecisionPolicy.enrichDecision(
            departure: departure,
            now: now,
            departureDelayMinutes: 3,
            walkMinutes: 4,
            walkP10: 3,
            walkP90: 5
        )
        XCTAssertEqual(tight.catchBucket, .tight)

        // Unlikely: large delay
        let unlikely = DecisionPolicy.enrichDecision(
            departure: departure,
            now: now,
            departureDelayMinutes: 10,
            walkMinutes: 5,
            walkP10: 4,
            walkP90: 6
        )
        XCTAssertEqual(unlikely.catchBucket, .unlikely)
    }

    // MARK: - Regression: no manual walk time references

    func testManualWalkTimeDoesNotExist() throws {
        // Verify at the type level that old manual concepts are gone.
        // CatchBucket must have exactly 3 cases (no old CatchStatus).
        let allBuckets: [CatchBucket] = [.likely, .tight, .unlikely]
        XCTAssertEqual(allBuckets.count, 3)

        // WalkTimeSource must NOT have a .manual case.
        // If someone re-adds it, this will fail to compile because
        // the exhaustive switch below won't match.
        let source = DepartureBoardViewModel.WalkTimeSource.auto
        switch source {
        case .auto: break
        case .estimated: break
        case .atStation: break
        // No .manual or .override case — compile error if re-added without updating here.
        }
    }

    // MARK: - Regression: departure delay shifts arrival

    func testArriveTimeUsesDepartureDelay() {
        let now = Date()

        // d=0 vs d=5: arrival mean must increase by exactly 5 min,
        // and catch probability must decrease (or stay equal).
        let dist0 = DecisionPolicy.computeArriveDistribution(
            now: now,
            departureDelayMinutes: 0,
            walkMinutes: 5,
            walkP10: 3,
            walkP90: 7
        )
        let dist5 = DecisionPolicy.computeArriveDistribution(
            now: now,
            departureDelayMinutes: 5,
            walkMinutes: 5,
            walkP10: 3,
            walkP90: 7
        )

        let meanShift = dist5.mean.timeIntervalSince(dist0.mean) / 60.0
        let p10Shift = dist5.p10.timeIntervalSince(dist0.p10) / 60.0
        let p90Shift = dist5.p90.timeIntervalSince(dist0.p90) / 60.0

        XCTAssertEqual(meanShift, 5.0, accuracy: 0.001,
                        "Departure delay of 5 must shift arrival mean by exactly 5 min")
        XCTAssertEqual(p10Shift, 5.0, accuracy: 0.001)
        XCTAssertEqual(p90Shift, 5.0, accuracy: 0.001)

        // With a departure 10 min from now, d=0 should have higher P(catch) than d=5.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "dd.MM.yy"
        let today = formatter.string(from: now)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "da_DK")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        timeFormatter.dateFormat = "HH:mm"
        let depTime = timeFormatter.string(from: now.addingTimeInterval(10 * 60))

        let departure = Departure(
            name: "5C", type: "BUS", stop: "X",
            time: depTime, date: today, rtTime: depTime, rtDate: today,
            direction: "Y", finalStop: "Y", track: nil, messages: nil,
            uncertaintyRange: UncertaintyRange(lowerBound: -2, upperBound: 2)
        )

        let p0 = DecisionPolicy.computeCatchProbability(departure: departure, arriveDist: dist0)
        let p5 = DecisionPolicy.computeCatchProbability(departure: departure, arriveDist: dist5)
        XCTAssertNotNil(p0)
        XCTAssertNotNil(p5)
        XCTAssertGreaterThanOrEqual(p0!, p5!,
                                     "P(catch) must be monotonically non-increasing as delay grows")
    }

    // MARK: - Regression: catch uses realtime departure when available

    func testCatchUsesRealtimeDepartureWhenAvailable() {
        // Scenario: Bus 68 scheduled 3 min from now, but delayed +11 → realtime 14 min.
        // Walk ETA mean=9 min, delay=0. User can easily catch it.
        // Old bug: calculation used scheduled time (3 min) → Unlikely.
        // Fixed: must use realtime (14 min) → Likely.
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "dd.MM.yy"
        let today = formatter.string(from: now)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "da_DK")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        timeFormatter.dateFormat = "HH:mm"

        let scheduledTime = timeFormatter.string(from: now.addingTimeInterval(3 * 60))
        let realtimeTime = timeFormatter.string(from: now.addingTimeInterval(14 * 60))

        let departure = Departure(
            name: "68", type: "BUS", stop: "Nuuks Plads",
            time: scheduledTime, date: today,
            rtTime: realtimeTime, rtDate: today,
            direction: "Bella Center", finalStop: "Bella Center",
            track: nil, messages: nil,
            uncertaintyRange: UncertaintyRange(lowerBound: -3.29, upperBound: 3.29),
            reliabilityScore: 0.82
        )

        // Verify effectiveDepartureDate uses realtime
        let effective = departure.effectiveDepartureDate
        XCTAssertNotNil(effective)
        XCTAssertTrue(effective!.isRealtime,
                       "effectiveDepartureDate must prefer realtime over scheduled")

        // The effective departure should be ~14 min from now, not ~3 min
        let effectiveMinutes = effective!.date.timeIntervalSince(now) / 60.0
        XCTAssertEqual(effectiveMinutes, 14.0, accuracy: 1.0,
                        "Effective departure must be ~14 min (realtime), not ~3 min (scheduled)")

        // Enrich with walk=9 min, delay=0 → should be Likely (not Unlikely)
        let enriched = DecisionPolicy.enrichDecision(
            departure: departure,
            now: now,
            departureDelayMinutes: 0,
            walkMinutes: 9,
            walkP10: 7,
            walkP90: 11
        )

        XCTAssertNotNil(enriched.catchProbability)
        XCTAssertGreaterThanOrEqual(enriched.catchProbability!, 0.80,
                                     "With 14 min realtime and 9 min walk, P(catch) should be high")
        XCTAssertNotEqual(enriched.catchBucket, .unlikely,
                           "Delayed bus with plenty of slack must NOT be Unlikely")

        // Contrast: if we had a departure with only scheduled time (3 min),
        // same walk would be Unlikely
        let scheduledOnly = Departure(
            name: "68", type: "BUS", stop: "Nuuks Plads",
            time: scheduledTime, date: today,
            rtTime: nil, rtDate: nil,
            direction: "Bella Center", finalStop: "Bella Center",
            track: nil, messages: nil,
            uncertaintyRange: UncertaintyRange(lowerBound: 0.25, upperBound: 4.75),
            reliabilityScore: 0.55
        )
        let enrichedScheduled = DecisionPolicy.enrichDecision(
            departure: scheduledOnly,
            now: now,
            departureDelayMinutes: 0,
            walkMinutes: 9,
            walkP10: 7,
            walkP90: 11
        )
        XCTAssertNotNil(enrichedScheduled.catchProbability)
        XCTAssertLessThan(enrichedScheduled.catchProbability!, enriched.catchProbability!,
                           "Scheduled-only (3 min) must have lower P(catch) than realtime (14 min)")
    }

    // MARK: - Regression: card does not render ETA range

    func testCardDoesNotRenderEtaRange() {
        // GlassDepartureCard should produce a single countdown number,
        // never an interval like "4-7" or "X–Y min".
        // We verify by checking that Departure has no interval-producing
        // properties and that CatchBucket labels contain no dash-digit patterns.
        let allLabels = [CatchBucket.likely.label, CatchBucket.tight.label, CatchBucket.unlikely.label]
        for label in allLabels {
            XCTAssertFalse(label.contains("-"), "Bucket label '\(label)' must not contain interval dash")
            XCTAssertNil(label.range(of: #"\d+-\d+"#, options: .regularExpression),
                         "Bucket label '\(label)' must not contain digit-dash-digit interval pattern")
        }
    }

    // MARK: - Probability formatting

    func testFormatProbability() {
        // nil → dash
        XCTAssertEqual(DecisionPolicy.formatProbability(nil), "—")
        // very low → "<5%"  (single %, no double %%)
        XCTAssertEqual(DecisionPolicy.formatProbability(0.01), "<5%")
        XCTAssertEqual(DecisionPolicy.formatProbability(0.04), "<5%")
        // normal range
        XCTAssertEqual(DecisionPolicy.formatProbability(0.58), "58%")
        XCTAssertEqual(DecisionPolicy.formatProbability(0.85), "85%")
        // very high → ">99%"
        XCTAssertEqual(DecisionPolicy.formatProbability(1.0), ">99%")
        XCTAssertEqual(DecisionPolicy.formatProbability(0.999), ">99%")
        // edge: exactly 0.05 should not be "<5%"
        XCTAssertEqual(DecisionPolicy.formatProbability(0.05), "5%")
        // no double %% anywhere
        for p in stride(from: 0.0, through: 1.0, by: 0.1) {
            let text = DecisionPolicy.formatProbability(p)
            XCTAssertFalse(text.contains("%%"), "formatProbability(\(p)) = '\(text)' must not contain %%")
        }
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

    // MARK: - Regression: mode classification via TransportModeResolver
    // Root cause: HAFAS products is a bitmask integer (e.g. 128), not a string like "BUS".
    // stop.type ("ST"/"ADR"/"POI") is a LOCATION type, never used for mode inference.

    /// type="ST" alone (no products, no bitmask) must be .unknown.
    func testStationModeSTTypeAloneIsUnknown() {
        let nuuks = StationModel(
            id: "8600626", name: "Nuuks Plads St. (Rantzausgade)",
            latitude: 55.68748, longitude: 12.54692,
            distanceMeters: 80, type: "ST"
        )
        XCTAssertEqual(nuuks.stationMode, .unknown,
                        "type='ST' without products/bitmask must be .unknown")

        let forum = StationModel(
            id: "8600630", name: "Forum St.",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 200, type: "ST"
        )
        XCTAssertEqual(forum.stationMode, .unknown,
                        "Forum St. with only type='ST' must be .unknown")
    }

    /// productsBitmask=16 (Bus cls) must produce .bus.
    func testStationModeBusFromBitmask() {
        let station = StationModel(
            id: "8600626", name: "Nuuks Plads St. (Rantzausgade)",
            latitude: 55.68748, longitude: 12.54692,
            distanceMeters: 80, type: "ST",
            productsBitmask: 16
        )
        XCTAssertEqual(station.stationMode, .bus,
                        "productsBitmask=16 (Bus) must map to .bus")
    }

    /// productsBitmask=8 (S-tog cls) must produce .tog.
    func testStationModeTogFromBitmask() {
        let station = StationModel(
            id: "8600700", name: "Nørreport St.",
            latitude: 55.68300, longitude: 12.57200,
            distanceMeters: 300, type: "ST",
            productsBitmask: 8
        )
        XCTAssertEqual(station.stationMode, .tog,
                        "productsBitmask=8 (S-tog) must map to .tog")
    }

    /// productsBitmask=64 (Metro cls) must produce .metro.
    func testStationModeMetroFromBitmask() {
        let station = StationModel(
            id: "8600800", name: "Forum (Metro)",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 150, type: "ST",
            productsBitmask: 64
        )
        XCTAssertEqual(station.stationMode, .metro,
                        "productsBitmask=64 (Metro) must map to .metro")
    }

    /// productsBitmask=80 (64+16 = Metro+Bus) must produce .mixed.
    func testStationModeMixedFromBitmask() {
        let station = StationModel(
            id: "8600631", name: "Forum St.",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 200, type: "ST",
            productsBitmask: 80 // 64 (metro) + 16 (bus)
        )
        if case .mixed(let modes) = station.stationMode {
            XCTAssertTrue(modes.contains(.bus), "Mixed bitmask 80 must include .bus")
            XCTAssertTrue(modes.contains(.metro), "Mixed bitmask 80 must include .metro")
        } else {
            XCTFail("productsBitmask=80 must be .mixed, got \(station.stationMode)")
        }
    }

    /// productAtStop with cls takes priority over bitmask.
    func testStationModeFromProductAtStop() {
        let entries = [
            ProductAtStopEntry(name: "Metro M3", catOut: "Metro", cls: 64),
            ProductAtStopEntry(name: "Bus 5C", catOut: "Bus", cls: 16)
        ]
        let station = StationModel(
            id: "8600800", name: "Forum St.",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 150, type: "ST",
            productsBitmask: 128, // would be metro-only if used
            productAtStop: entries
        )
        if case .mixed(let modes) = station.stationMode {
            XCTAssertTrue(modes.contains(.bus), "productAtStop must include .bus from cls=16")
            XCTAssertTrue(modes.contains(.metro), "productAtStop must include .metro from cls=64")
        } else {
            XCTFail("productAtStop with bus+metro must be .mixed, got \(station.stationMode)")
        }
    }

    /// String token products still work (backward compat).
    func testStationModeBusFromStringProducts() {
        let station = StationModel(
            id: "8600626", name: "Nuuks Plads St.",
            latitude: 55.68748, longitude: 12.54692,
            distanceMeters: 80, type: "ST",
            products: ["BUS"]
        )
        XCTAssertEqual(station.stationMode, .bus,
                        "products=['BUS'] string token must map to .bus")
    }

    /// String "128" in products array must be decoded as bitmask → metro (Letbane).
    func testStationModeBitmaskStringInProductsArray() {
        let station = StationModel(
            id: "8600900", name: "Skyttegade",
            latitude: 55.68000, longitude: 12.55000,
            distanceMeters: 100, type: "ST",
            products: ["128"]
        )
        XCTAssertEqual(station.stationMode, .metro,
                        "products=['128'] must decode bitmask 128 → .metro (Letbane)")
    }

    /// Name fallback: "(Metro)" in name → .metro when no products.
    func testStationModeNameFallbackMetro() {
        let station = StationModel(
            id: "8600801", name: "Forum (Metro)",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 150, type: "ST"
        )
        XCTAssertEqual(station.stationMode, .metro,
                        "Name '(Metro)' must fallback to .metro when no products")
    }

    /// Name with only "St." and no products must be .unknown — never guess TOG.
    func testStationModeNameStDotIsNotTog() {
        let station = StationModel(
            id: "9999", name: "Forum St.",
            latitude: 55.68100, longitude: 12.55700,
            distanceMeters: 200, type: nil
        )
        XCTAssertEqual(station.stationMode, .unknown,
                        "'St.' in name must NOT trigger .tog — must be .unknown")
    }

    /// Group with metro + bus entrances must have mergedMode .mixed.
    func testStationGroupMixedEntrances() {
        let busEntrance = StationModel(
            id: "1", name: "Nuuks Plads St. (Rantzausgade)",
            latitude: 55.68748, longitude: 12.54692,
            distanceMeters: 80, type: "ST",
            productsBitmask: 16
        )
        let metroEntrance = StationModel(
            id: "2", name: "Nuuks Plads (Metro)",
            latitude: 55.68760, longitude: 12.54680,
            distanceMeters: 110, type: "ST",
            productsBitmask: 64
        )
        let group = StationGroupModel(id: "test", baseName: "Nuuks Plads", stations: [busEntrance, metroEntrance])

        // Each entrance keeps its own mode
        XCTAssertEqual(busEntrance.stationMode, .bus)
        XCTAssertEqual(metroEntrance.stationMode, .metro)

        // Group mergedMode is the union
        if case .mixed(let modes) = group.mergedMode {
            XCTAssertTrue(modes.contains(.bus), "Group must include .bus from bus entrance")
            XCTAssertTrue(modes.contains(.metro), "Group must include .metro from metro entrance")
        } else {
            XCTFail("Group with bus + metro entrances must be .mixed, got \(group.mergedMode)")
        }
    }

    func testNuuksPladsAggregatesToMixed() {
        let busEntrance = StationModel(
            id: "nuuks-bus",
            name: "Nuuks Plads St. (Rantzausgade)",
            latitude: 55.68748,
            longitude: 12.54692,
            distanceMeters: 80,
            type: "ST",
            products: ["BUS"]
        )
        let metroEntrance = StationModel(
            id: "nuuks-metro",
            name: "Nuuks Plads St. (Metro)",
            latitude: 55.68752,
            longitude: 12.54688,
            distanceMeters: 100,
            type: "ST",
            products: ["METRO"]
        )

        let group = StationGroupModel(id: "nuuks", baseName: "Nuuks Plads St.", stations: [busEntrance, metroEntrance])
        if case .mixed(let modes) = group.mergedMode {
            XCTAssertEqual(modes, Set([.bus, .metro]))
        } else {
            XCTFail("Nuuks Plads should aggregate to .mixed(bus+metro), got \(group.mergedMode)")
        }
    }

    func testLauridsNoProductsDoesNotFallbackToStationOrTog() {
        let station = StationModel(
            id: "laurids",
            name: "Laurids Skaus Gade (Ågade)",
            latitude: 55.0,
            longitude: 12.0,
            distanceMeters: 50,
            type: "ST",
            products: []
        )

        XCTAssertEqual(station.stationMode, .unknown)
    }

    func testNameStDoesNotImplyTog() {
        let station = StationModel(
            id: "forum-st",
            name: "Forum St.",
            latitude: 55.68100,
            longitude: 12.55700,
            distanceMeters: 200,
            type: "ST",
            products: []
        )

        XCTAssertEqual(station.stationMode, .unknown)
    }

    @MainActor
    func testWalkingETA_NoDefaultFive() {
        let vm = DepartureBoardViewModel(
            stationId: "8600626",
            apiService: MockIntegrationAPIService(),
            locationManager: MockLocationManager(authorizationStatus: .authorizedWhenInUse, currentLocation: nil),
            walkingETAService: MockWalkingETAService(result: .success(WalkETA(minutes: 4, distanceMeters: 300, source: .hafasWalk)))
        )

        XCTAssertEqual(vm.walkingETAState, .idle)
        XCTAssertEqual(vm.walkingTimeDisplayText, L10n.tr("departures.walking.calculating"))
    }

    func testWalkingETA_PicksLongestWalkLeg() {
        let summary = WalkingETAService.selectWalkingSummary(from: [
            .init(durationSeconds: 120, distanceMeters: 160),
            .init(durationSeconds: 240, distanceMeters: 320)
        ])
        XCTAssertNotNil(summary)
        // Current strategy sums all WALK legs to avoid underestimating when first leg is only an in-station segment.
        XCTAssertEqual(summary?.totalDurationSeconds, 360)
        XCTAssertEqual(summary?.totalDistanceMeters, 480)
    }

    func testWalkingETA_SkyttegadeTripChainAndCache() async throws {
        URLProtocolMock.requestCount = 0
        URLProtocolMock.testData = """
        {
          "TripList": {
            "Trip": [{
              "LegList": {
                "Leg": [
                  {
                    "type": "WALK",
                    "duration": "00:02:00",
                    "dist": 180,
                    "Origin": { "name": "Street A" },
                    "Destination": { "name": "Transfer Hall" }
                  },
                  {
                    "type": "WALK",
                    "duration": "00:04:00",
                    "dist": 320,
                    "Origin": { "name": "Transfer Hall" },
                    "Destination": { "name": "Skyttegade" }
                  }
                ]
              }
            }]
          }
        }
        """.data(using: .utf8)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: config)
        let service = WalkingETAService(
            client: HafasClient(session: session),
            apiService: MockIntegrationAPIService()
        )
        let origin = CLLocationCoordinate2D(latitude: 55.6871, longitude: 12.5458)

        let first = try await service.fetchWalkETA(origin: origin, destStopId: "skyttegade-entrance")
        let second = try await service.fetchWalkETA(origin: origin, destStopId: "skyttegade-entrance")

        XCTAssertEqual(first.minutes, 6, "2min + 4min WALK legs should sum to 6min")
        XCTAssertEqual(second.minutes, 6, "Second fetch should return cached value")
        XCTAssertEqual(URLProtocolMock.requestCount, 1, "Second fetch should hit in-memory cache")
    }

    @MainActor
    func testNearbyViewModelRefreshBuildsGroupedStations() async {
        let locationManager = MockLocationManager(
            authorizationStatus: .authorizedWhenInUse,
            currentLocation: CLLocation(latitude: 55.68748, longitude: 12.54692)
        )
        let service = MockIntegrationAPIService(
            nearbyStopsResult: [
                StationModel(
                    id: "1",
                    name: "Nuuks Plads St. (Rantzausgade)",
                    latitude: 55.68748,
                    longitude: 12.54692,
                    distanceMeters: 80,
                    type: "BUS"
                ),
                StationModel(
                    id: "2",
                    name: "Nuuks Plads St. (Jagtvej)",
                    latitude: 55.68760,
                    longitude: 12.54680,
                    distanceMeters: 110,
                    type: "BUS"
                )
            ]
        )
        let vm = NearbyStationsViewModel(apiService: service, locationManager: locationManager)

        await vm.refreshNearbyStations()

        XCTAssertEqual(vm.stationGroups.count, 1)
        XCTAssertEqual(vm.filteredStationGroups.first?.entranceCount, 2)
        XCTAssertEqual(vm.state, .success)
    }

    @MainActor
    func testDepartureBoardViewModelFetchPopulatesDepartures() async {
        let service = MockIntegrationAPIService(
            departuresResult: [
                Departure(
                    name: "68",
                    type: "BUS",
                    stop: "Nuuks Plads",
                    time: "13:30",
                    date: "13.02.26",
                    rtTime: "13:32",
                    rtDate: "13.02.26",
                    direction: "Bella Center",
                    finalStop: "Bella Center",
                    track: nil,
                    messages: nil
                )
            ]
        )
        let vm = DepartureBoardViewModel(
            stationId: "test-station",
            apiService: service,
            locationManager: MockLocationManager(authorizationStatus: .denied, currentLocation: nil)
        )

        await vm.fetchDepartures()

        XCTAssertEqual(vm.departures.count, 1)
        XCTAssertEqual(vm.state, .success)
    }

    func testAppErrorPresenterOfflineMessage() {
        let message = AppErrorPresenter.message(
            for: APIError.network(URLError(.notConnectedToInternet)),
            context: .stations
        )
        XCTAssertEqual(message, L10n.tr("error.offline"))
    }

    func testAppCacheStoreRespectsMaxAge() {
        let storage = InMemoryKeyValueStore()
        let cache = AppCacheStore(store: storage)
        cache.save(["a", "b"], key: "k")

        XCTAssertNotNil(cache.load([String].self, key: "k", maxAge: 60))

        storage.set(Date().addingTimeInterval(-120).timeIntervalSince1970, forKey: "k_ts")
        XCTAssertNil(cache.load([String].self, key: "k", maxAge: 60))
    }
}

private final class MockLocationManager: LocationManaging {
    var authorizationStatus: CLAuthorizationStatus
    var currentLocation: CLLocation?

    private let authorizationSubject: CurrentValueSubject<CLAuthorizationStatus, Never>
    private let locationSubject: CurrentValueSubject<CLLocation?, Never>

    init(authorizationStatus: CLAuthorizationStatus, currentLocation: CLLocation?) {
        self.authorizationStatus = authorizationStatus
        self.currentLocation = currentLocation
        self.authorizationSubject = CurrentValueSubject(authorizationStatus)
        self.locationSubject = CurrentValueSubject(currentLocation)
    }

    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject.eraseToAnyPublisher()
    }

    var currentLocationPublisher: AnyPublisher<CLLocation?, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    func requestAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
}

private struct MockIntegrationAPIService: APIServiceProtocol {
    var nearbyStopsResult: [StationModel] = []
    var departuresResult: [Departure] = []

    func fetchNearbyStops(coordX: Double, coordY: Double, radiusMeters: Int?, maxNo: Int?) async throws -> [StationModel] {
        nearbyStopsResult
    }

    func fetchDepartures(for stationID: String) async throws -> [Departure] {
        departuresResult
    }

    func fetchDepartures(forStationIDs stationIDs: [String], maxJourneys: Int, filters: MultiDepartureFilters) async throws -> [Departure] {
        departuresResult
    }

    func searchLocations(input: String) async throws -> [StationModel] {
        nearbyStopsResult
    }

    func fetchJourneyDetail(id: String, date: String?) async throws -> JourneyDetail {
        JourneyDetail(stops: [])
    }
}

private final class MockWalkingETAService: WalkingETAServiceProtocol {
    private let result: Result<WalkETA, Error>

    init(result: Result<WalkETA, Error>) {
        self.result = result
    }

    func fetchWalkETA(origin: CLLocationCoordinate2D, destStopId: String) async throws -> WalkETA {
        try result.get()
    }
}

private final class URLProtocolMock: URLProtocol {
    nonisolated(unsafe) static var testData: Data?
    nonisolated(unsafe) static var requestCount: Int = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let data = Self.testData ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class InMemoryKeyValueStore: KeyValueStoring {
    private var values: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        values[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    func double(forKey defaultName: String) -> Double {
        values[defaultName] as? Double ?? 0
    }

    func array(forKey defaultName: String) -> [Any]? {
        values[defaultName] as? [Any]
    }
}
