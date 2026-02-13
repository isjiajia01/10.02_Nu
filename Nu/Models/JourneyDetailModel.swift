import Foundation

struct JourneyDetailResponse: Decodable {
    let journeyDetail: JourneyDetail

    enum CodingKeys: String, CodingKey {
        case journeyDetail = "JourneyDetail"
        case journeyDetailLower = "journeyDetail"
        case result = "Result"
        case resultLower = "result"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        journeyDetail =
            (try? container.decode(JourneyDetail.self, forKey: .journeyDetail))
            ?? (try? container.decode(JourneyDetail.self, forKey: .journeyDetailLower))
            ?? (try? container.decode(JourneyDetail.self, forKey: .result))
            ?? (try? container.decode(JourneyDetail.self, forKey: .resultLower))
            // Rejseplanen 某些部署会直接返回顶层 `Stops`（无 JourneyDetail 包裹）。
            ?? (try? JourneyDetail(from: decoder))
            ?? JourneyDetail(stops: [])
    }
}

struct JourneyDetail: Decodable, Hashable {
    let stops: [JourneyStop]

    enum CodingKeys: String, CodingKey {
        case stop = "Stop"
        case stopLower = "stop"
        case stopsContainer = "Stops"
        case stopsContainerLower = "stops"
        case journeyStops = "JourneyStops"
        case journeyStopsLower = "journeyStops"
        case leg = "Leg"
        case legLower = "leg"
        case passList = "PassList"
        case passListLower = "passList"
    }

    private struct StopsContainer: Decodable {
        let stops: [JourneyStop]

        enum CodingKeys: String, CodingKey {
            case stop = "Stop"
            case stopLower = "stop"
            case passList = "PassList"
            case passListLower = "passList"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let list = try? container.decode([JourneyStop].self, forKey: .stop) {
                stops = list
            } else if let list = try? container.decode([JourneyStop].self, forKey: .stopLower) {
                stops = list
            } else if let single = try? container.decode(JourneyStop.self, forKey: .stop) {
                stops = [single]
            } else if let single = try? container.decode(JourneyStop.self, forKey: .stopLower) {
                stops = [single]
            } else if let pass = try? container.decode(StopsContainer.self, forKey: .passList) {
                stops = pass.stops
            } else if let pass = try? container.decode(StopsContainer.self, forKey: .passListLower) {
                stops = pass.stops
            } else {
                stops = []
            }
        }
    }

    init(stops: [JourneyStop]) {
        self.stops = stops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode(StopsContainer.self, forKey: .stopsContainer) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .stopsContainerLower) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .journeyStops) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .journeyStopsLower) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .passList) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .passListLower) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .leg) {
            stops = nested.stops
        } else if let nested = try? container.decode(StopsContainer.self, forKey: .legLower) {
            stops = nested.stops
        } else if let list = try? container.decode([JourneyStop].self, forKey: .stop) {
            stops = list
        } else if let list = try? container.decode([JourneyStop].self, forKey: .stopLower) {
            stops = list
        } else if let single = try? container.decode(JourneyStop.self, forKey: .stop) {
            stops = [single]
        } else if let single = try? container.decode(JourneyStop.self, forKey: .stopLower) {
            stops = [single]
        } else {
            stops = []
        }
    }

}

struct JourneyStop: Codable, Hashable {
    let id: String?
    let name: String
    let routeIdx: Int?
    let arrTime: String?
    let arrDate: String?
    let rtArrTime: String?
    let depTime: String?
    let depDate: String?
    let rtDepTime: String?
    let track: String?
    let rtTrack: String?
    let lat: Double?
    let lon: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case extId
        case name
        case routeIdx
        case arrTime
        case arrDate
        case rtArrTime
        case depTime
        case depDate
        case rtDepTime
        case track
        case rtTrack
        case lat
        case lon
        case x
        case y
    }

    init(
        id: String?,
        name: String,
        routeIdx: Int? = nil,
        arrTime: String?,
        arrDate: String? = nil,
        rtArrTime: String? = nil,
        depTime: String?,
        depDate: String? = nil,
        rtDepTime: String? = nil,
        track: String?,
        rtTrack: String? = nil,
        lat: Double? = nil,
        lon: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.routeIdx = routeIdx
        self.arrTime = arrTime
        self.arrDate = arrDate
        self.rtArrTime = rtArrTime
        self.depTime = depTime
        self.depDate = depDate
        self.rtDepTime = rtDepTime
        self.track = track
        self.rtTrack = rtTrack
        self.lat = lat
        self.lon = lon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id))
            ?? (try? container.decode(String.self, forKey: .extId))
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown Stop"
        routeIdx = try? container.decode(Int.self, forKey: .routeIdx)
        arrTime = try? container.decode(String.self, forKey: .arrTime)
        arrDate = try? container.decode(String.self, forKey: .arrDate)
        rtArrTime = try? container.decode(String.self, forKey: .rtArrTime)
        depTime = try? container.decode(String.self, forKey: .depTime)
        depDate = try? container.decode(String.self, forKey: .depDate)
        rtDepTime = try? container.decode(String.self, forKey: .rtDepTime)
        track = try? container.decode(String.self, forKey: .track)
        rtTrack = try? container.decode(String.self, forKey: .rtTrack)
        if let lat = try? container.decode(Double.self, forKey: .lat) {
            self.lat = lat
        } else if let y = try? container.decode(Double.self, forKey: .y) {
            self.lat = abs(y) > 90 ? y / 1_000_000.0 : y
        } else {
            self.lat = nil
        }
        if let lon = try? container.decode(Double.self, forKey: .lon) {
            self.lon = lon
        } else if let x = try? container.decode(Double.self, forKey: .x) {
            self.lon = abs(x) > 180 ? x / 1_000_000.0 : x
        } else {
            self.lon = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(routeIdx, forKey: .routeIdx)
        try container.encodeIfPresent(arrTime, forKey: .arrTime)
        try container.encodeIfPresent(arrDate, forKey: .arrDate)
        try container.encodeIfPresent(rtArrTime, forKey: .rtArrTime)
        try container.encodeIfPresent(depTime, forKey: .depTime)
        try container.encodeIfPresent(depDate, forKey: .depDate)
        try container.encodeIfPresent(rtDepTime, forKey: .rtDepTime)
        try container.encodeIfPresent(track, forKey: .track)
        try container.encodeIfPresent(rtTrack, forKey: .rtTrack)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
    }
}
