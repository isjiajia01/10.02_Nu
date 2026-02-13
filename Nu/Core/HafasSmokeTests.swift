import Foundation

#if DEBUG
enum HafasSmokeTests {
    static func runIfEnabled() {
        let env = ProcessInfo.processInfo.environment["NU_RUN_HAFAS_SMOKE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard env == "1" || env == "true" || env == "yes" else { return }

        AppLogger.debug("[SMOKE] starting Hafas smoke tests")
        testJourneyDetailIDEncoding()
        testJourneyDetailTopLevelStopsDecoding()
        testScrollTimePlusOneMinute()
        testFavoriteIDPersistence()
        testResWrapperDecoding()
        testDelayCalculation()
        AppLogger.debug("[SMOKE] Hafas smoke tests passed")
    }

    private static func testJourneyDetailIDEncoding() {
        let client = HafasClient()
        let journeyID = "2|123|456|0|86|RT#1"
        let url = try! client.makeURL(
            service: .journeyDetail,
            queryItems: [URLQueryItem(name: "id", value: journeyID)]
        )
        assert(url.absoluteString.contains("id="), "journeyDetail should use id query param")
        assert(url.absoluteString.contains("%7C"), "journeyDetail id must encode '|' as %7C")
    }

    private static func testJourneyDetailTopLevelStopsDecoding() {
        let raw = """
        {
          "Stops": {
            "Stop": [
              {
                "id": "A=1@L=2256@",
                "name": "Origin",
                "depTime": "13:20:00",
                "depDate": "2026-02-13",
                "routeIdx": 0
              },
              {
                "id": "A=1@L=3155@",
                "name": "Destination",
                "arrTime": "14:04:00",
                "arrDate": "2026-02-13",
                "routeIdx": 16
              }
            ]
          }
        }
        """
        let data = raw.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(JourneyDetailResponse.self, from: data)
        assert(decoded.journeyDetail.stops.count == 2, "top-level Stops should decode into journeyDetail.stops")
    }

    private static func testScrollTimePlusOneMinute() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        let date = formatter.string(from: Date())

        let deps = [
            Departure(
                name: "19",
                type: "BUS",
                stop: "X",
                time: "10:00",
                date: date,
                rtTime: nil,
                rtDate: nil,
                direction: "Y",
                finalStop: "Y",
                track: nil,
                messages: nil
            ),
            Departure(
                name: "22",
                type: "BUS",
                stop: "X",
                time: "10:10",
                date: date,
                rtTime: nil,
                rtDate: nil,
                direction: "Y",
                finalStop: "Y",
                track: nil,
                messages: nil
            )
        ]
        let next = DeparturePaging.nextPageTime(from: deps)
        assert(next != nil, "next page time should not be nil")
    }

    private static func testFavoriteIDPersistence() {
        let station = FavoriteStation(id: "123", extId: "008600001", globalId: "A=1@L=8600001@", name: "Test", type: "BUS")
        let data = try! JSONEncoder().encode(station)
        let decoded = try! JSONDecoder().decode(FavoriteStation.self, from: data)
        assert(decoded.id == "123", "favorite id should persist")
        assert(decoded.extId == "008600001", "favorite extId should persist")
        assert(decoded.globalId == "A=1@L=8600001@", "favorite globalId should persist")
    }

    private static func testResWrapperDecoding() {
        struct Payload: Decodable {
            let value: Int
        }
        let data = #"{"res":{"value":7}}"#.data(using: .utf8)!
        let decoded = try! HafasDecoder.decode(Payload.self, from: data, decoder: JSONDecoder())
        assert(decoded.value == 7, "res wrapper decode failed")
    }

    private static func testDelayCalculation() {
        let dep = Departure(
            name: "5C",
            type: "BUS",
            stop: "X",
            time: "10:00",
            date: "13.02.26",
            rtTime: "10:05",
            rtDate: "13.02.26",
            direction: "Y",
            finalStop: "Y",
            track: nil,
            messages: nil
        )
        assert(dep.delayMinutes == 5, "delayMinutes should be 5")
    }
}
#endif
