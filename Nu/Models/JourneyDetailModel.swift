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
    let zone: String?
    let tariffZone: String?
    let tariffZones: [String]?
    let type: String?
    let products: String?
    let notes: [JourneyStopNote]?

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
        case zone
        case tariffZone
        case zoneNo
        case tariffZones
        case type
        case products
        case notes = "Notes"
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
        lon: Double? = nil,
        zone: String? = nil,
        tariffZone: String? = nil,
        tariffZones: [String]? = nil,
        type: String? = nil,
        products: String? = nil,
        notes: [JourneyStopNote]? = nil
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
        self.zone = zone
        self.tariffZone = tariffZone
        self.tariffZones = tariffZones
        self.type = type
        self.products = products
        self.notes = notes
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
        if let zoneText = try? container.decode(String.self, forKey: .zone) {
            zone = zoneText
        } else if let zoneInt = try? container.decode(Int.self, forKey: .zone) {
            zone = String(zoneInt)
        } else if let zoneText = try? container.decode(String.self, forKey: .tariffZone) {
            zone = zoneText
        } else if let zoneInt = try? container.decode(Int.self, forKey: .tariffZone) {
            zone = String(zoneInt)
        } else if let zoneText = try? container.decode(String.self, forKey: .zoneNo) {
            zone = zoneText
        } else if let zoneInt = try? container.decode(Int.self, forKey: .zoneNo) {
            zone = String(zoneInt)
        } else {
            zone = nil
        }
        if let text = try? container.decode(String.self, forKey: .tariffZone) {
            tariffZone = text
        } else if let value = try? container.decode(Int.self, forKey: .tariffZone) {
            tariffZone = String(value)
        } else {
            tariffZone = nil
        }
        tariffZones = Self.decodeStringArray(container: container, key: .tariffZones)
        type = try? container.decode(String.self, forKey: .type)
        if let productsList = Self.decodeStringArray(container: container, key: .products), !productsList.isEmpty {
            products = productsList.joined(separator: ",")
        } else if let productsText = try? container.decode(String.self, forKey: .products) {
            products = productsText
        } else {
            products = nil
        }
        notes = Self.decodeNotes(container: container, key: .notes)
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
        try container.encodeIfPresent(zone, forKey: .zone)
        try container.encodeIfPresent(tariffZone, forKey: .tariffZone)
        try container.encodeIfPresent(tariffZones, forKey: .tariffZones)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(products, forKey: .products)
    }

    private static func decodeStringArray(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [String]? {
        if let list = try? container.decode([String].self, forKey: key) {
            return list
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return [text]
        }
        if let number = try? container.decode(Int.self, forKey: key) {
            return [String(number)]
        }
        return nil
    }

    private static func decodeNotes(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [JourneyStopNote]? {
        struct NoteContainer: Decodable {
            let notes: [JourneyStopNote]
            enum CodingKeys: String, CodingKey { case notes = "Note" }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let list = try? c.decode([JourneyStopNote].self, forKey: .notes) {
                    notes = list
                } else if let single = try? c.decode(JourneyStopNote.self, forKey: .notes) {
                    notes = [single]
                } else {
                    notes = []
                }
            }
        }
        if let wrapper = try? container.decode(NoteContainer.self, forKey: key) {
            return wrapper.notes.isEmpty ? nil : wrapper.notes
        }
        return nil
    }
}

struct JourneyStopNote: Codable, Hashable {
    let key: String?
    let value: String?
    let type: String?
    let textName: String?

    enum CodingKeys: String, CodingKey {
        case key
        case value
        case type
        case textName = "txtN"
    }
}

// MARK: - Journey Position

struct JourneyPosResponse: Decodable {
    let journeys: [JourneyVehiclePayload]

    enum CodingKeys: String, CodingKey {
        case journeyPos = "JourneyPos"
        case journeyPosLower = "journeyPos"
        case journey = "Journey"
        case journeyLower = "journey"
        case journeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let wrapper = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .journeyPos) {
            journeys = JourneyPosResponse.decodeJourneys(from: wrapper)
            return
        }
        if let wrapper = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .journeyPosLower) {
            journeys = JourneyPosResponse.decodeJourneys(from: wrapper)
            return
        }
        journeys = JourneyPosResponse.decodeJourneys(from: container)
    }

    private static func decodeJourneys(from container: KeyedDecodingContainer<CodingKeys>) -> [JourneyVehiclePayload] {
        if let list = try? container.decode([JourneyVehiclePayload].self, forKey: .journey) { return list }
        if let list = try? container.decode([JourneyVehiclePayload].self, forKey: .journeyLower) { return list }
        if let list = try? container.decode([JourneyVehiclePayload].self, forKey: .journeys) { return list }
        if let single = try? container.decode(JourneyVehiclePayload.self, forKey: .journey) { return [single] }
        if let single = try? container.decode(JourneyVehiclePayload.self, forKey: .journeyLower) { return [single] }
        return []
    }
}

struct JourneyVehiclePayload: Decodable {
    let jid: String?
    let line: String?
    let direction: String?
    let lat: Double?
    let lon: Double?
    let when: String?
    let realtimeType: String?
    let idHint: String?
    let isRealtimeFlag: Bool?
    let isReportedFlag: Bool?
    let isCalculatedFlag: Bool?
    let positionModeHint: String?
    let heading: Double?
    let stopName: String?
    let nextStopName: String?
    let journeyDetailRef: String?
    let originName: String?
    let destinationName: String?
    let productNumber: String?
    let productOperator: String?

    enum CodingKeys: String, CodingKey {
        case jid
        case id
        case line
        case name
        case direction
        case dir
        case lat
        case lon
        case x
        case y
        case time
        case rtTime
        case timestamp
        case t
        case locationType
        case posType
        case product
        case isRealtime
        case realtime
        case rt
        case reported
        case isReported
        case calc
        case isCalculated
        case positionMode
        case mode
        case heading
        case bearing
        case headingDeg
        case stop
        case currentStop
        case stopName
        case nextStop
        case nextStopName
        case journeyDetailRef = "JourneyDetailRef"
        case journeyOrigin = "JourneyOrigin"
        case journeyDestination = "JourneyDestination"
        case productNode = "Product"
        case ref
        case num
        case operatorCode = "operatorCode"
        case operatorName = "operator"
        case position = "Position"
        case positionLower = "position"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jid = (try? container.decode(String.self, forKey: .jid))
            ?? (try? container.decode(String.self, forKey: .id))
        line = (try? container.decode(String.self, forKey: .line))
            ?? (try? container.decode(String.self, forKey: .name))
        direction = (try? container.decode(String.self, forKey: .direction))
            ?? (try? container.decode(String.self, forKey: .dir))

        let topLat = Self.decodeCoordinate(container: container, primary: .lat, fallback: .y, isLatitude: true)
        let topLon = Self.decodeCoordinate(container: container, primary: .lon, fallback: .x, isLatitude: false)

        if topLat != nil || topLon != nil {
            lat = topLat
            lon = topLon
        } else if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .position) {
            lat = Self.decodeCoordinate(container: nested, primary: .lat, fallback: .y, isLatitude: true)
            lon = Self.decodeCoordinate(container: nested, primary: .lon, fallback: .x, isLatitude: false)
        } else if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .positionLower) {
            lat = Self.decodeCoordinate(container: nested, primary: .lat, fallback: .y, isLatitude: true)
            lon = Self.decodeCoordinate(container: nested, primary: .lon, fallback: .x, isLatitude: false)
        } else {
            lat = nil
            lon = nil
        }

        when = (try? container.decode(String.self, forKey: .timestamp))
            ?? (try? container.decode(String.self, forKey: .rtTime))
            ?? (try? container.decode(String.self, forKey: .time))
            ?? (try? container.decode(String.self, forKey: .t))
        realtimeType = (try? container.decode(String.self, forKey: .locationType))
            ?? (try? container.decode(String.self, forKey: .posType))
            ?? (try? container.decode(String.self, forKey: .product))
        idHint = (try? container.decode(String.self, forKey: .id))
        isRealtimeFlag = Self.decodeBool(container: container, keys: [.isRealtime, .realtime, .rt])
        isReportedFlag = Self.decodeBool(container: container, keys: [.reported, .isReported])
        isCalculatedFlag = Self.decodeBool(container: container, keys: [.calc, .isCalculated])
        positionModeHint = (try? container.decode(String.self, forKey: .positionMode))
            ?? (try? container.decode(String.self, forKey: .mode))
        heading = Self.decodeNumber(container: container, key: .heading)
            ?? Self.decodeNumber(container: container, key: .bearing)
            ?? Self.decodeNumber(container: container, key: .headingDeg)
        stopName = (try? container.decode(String.self, forKey: .stop))
            ?? (try? container.decode(String.self, forKey: .currentStop))
            ?? (try? container.decode(String.self, forKey: .stopName))
        nextStopName = (try? container.decode(String.self, forKey: .nextStop))
            ?? (try? container.decode(String.self, forKey: .nextStopName))

        if let refContainer = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .journeyDetailRef) {
            journeyDetailRef = (try? refContainer.decode(String.self, forKey: .ref))
        } else {
            journeyDetailRef = nil
        }

        if let originContainer = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .journeyOrigin) {
            originName = (try? originContainer.decode(String.self, forKey: .name))
        } else {
            originName = nil
        }

        if let destinationContainer = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .journeyDestination) {
            destinationName = (try? destinationContainer.decode(String.self, forKey: .name))
        } else {
            destinationName = nil
        }

        if let productContainer = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .productNode) {
            productNumber = (try? productContainer.decode(String.self, forKey: .num))
            productOperator = (try? productContainer.decode(String.self, forKey: .operatorCode))
                ?? (try? productContainer.decode(String.self, forKey: .operatorName))
        } else {
            productNumber = nil
            productOperator = nil
        }
    }

    private static func decodeCoordinate(
        container: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        fallback: CodingKeys,
        isLatitude: Bool
    ) -> Double? {
        let raw = decodeNumber(container: container, key: primary) ?? decodeNumber(container: container, key: fallback)
        guard var raw else { return nil }
        let limit = isLatitude ? 90.0 : 180.0
        if abs(raw) > limit {
            raw /= 1_000_000.0
            if abs(raw) > limit {
                #if DEBUG
                AppLogger.debug("[JourneyPos] drop invalid coord key=\(primary.stringValue) raw=\(raw)")
                #endif
                return nil
            }
        }
        return raw
    }

    private static func decodeNumber(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let v = try? container.decode(Double.self, forKey: key) { return v }
        if let v = try? container.decode(Int.self, forKey: key) { return Double(v) }
        if let v = try? container.decode(String.self, forKey: key) { return Double(v) }
        return nil
    }

    private static func decodeBool(
        container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Bool? {
        for key in keys {
            if let b = try? container.decode(Bool.self, forKey: key) {
                return b
            }
            if let i = try? container.decode(Int.self, forKey: key) {
                return i != 0
            }
            if let s = try? container.decode(String.self, forKey: key) {
                let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["1", "true", "yes", "reported", "rt"].contains(lower) { return true }
                if ["0", "false", "no", "calc", "estimated"].contains(lower) { return false }
            }
        }
        return nil
    }
}
