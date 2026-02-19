import Foundation

/// Rejseplanen 真实 API 服务实现。
///
/// 关键点：
/// - `departureBoard` 请求固定使用 `format=json`（由 `APIEndpoint` 注入）。
/// - `nearbyStops` 对齐 Rejseplanen 常见 JSON 结构：`LocationList -> StopLocation`。
/// - 对 `StopLocation` 做数组/单对象/空值容错。
final class RejseplanenAPIService: APIServiceProtocol {
    private let client: HafasClient

    nonisolated init(client: HafasClient = HafasClient()) {
        self.client = client
    }

    /// 获取附近站点。
    func fetchNearbyStops(
        coordX: Double,
        coordY: Double,
        radiusMeters: Int? = nil,
        maxNo: Int? = nil
    ) async throws -> [StationModel] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "originCoordLong", value: String(coordX)),
            URLQueryItem(name: "originCoordLat", value: String(coordY)),
            URLQueryItem(name: "maxNo", value: String(maxNo ?? 30))
        ]
        if let radiusMeters {
            query.append(URLQueryItem(name: "r", value: String(radiusMeters)))
        }

        let response: HafasResponse<NearbyStopsResponse> = try await client.request(
            service: .nearbyStops,
            queryItems: query,
            context: HafasRequestContext(context: [
                "feature": "nearbyStops"
            ])
        )

        return response.value.stopLocations.compactMap { stop in
            guard let lon = stop.longitude, let lat = stop.latitude else {
                return nil
            }

            return StationModel(
                id: stop.id,
                extId: stop.extId,
                globalId: stop.globalId,
                name: stop.name,
                latitude: lat,
                longitude: lon,
                distanceMeters: stop.distanceMeters,
                type: stop.type,
                products: stop.products,
                productsBitmask: stop.productsBitmask,
                productAtStop: stop.productAtStop,
                category: stop.category,
                zone: stop.zone,
                zoneSource: stop.zoneSource,
                stationGroupId: stop.stationGroupId
            )
        }
    }

    /// 获取站点发车信息。
    func fetchDepartures(for stationID: String) async throws -> [Departure] {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "da_DK")
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "da_DK")
        timeFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        timeFormatter.dateFormat = "HH:mm"

        let response: HafasResponse<DepartureBoardResponse> = try await client.request(
            service: .departureBoard,
            queryItems: [
                URLQueryItem(name: "id", value: stationID),
                URLQueryItem(name: "date", value: dateFormatter.string(from: now)),
                URLQueryItem(name: "time", value: timeFormatter.string(from: now)),
                URLQueryItem(name: "duration", value: "60"),
                URLQueryItem(name: "maxJourneys", value: "20"),
                URLQueryItem(name: "rtMode", value: "SERVER_DEFAULT"),
                URLQueryItem(name: "type", value: "DEP_EQUIVS"),
                URLQueryItem(name: "passlist", value: "1"),
                URLQueryItem(name: "passlistMaxStops", value: "60")
            ],
            context: HafasRequestContext(context: [
                "feature": "departureBoard",
                "stationId": stationID
            ])
        )
        let departures = response.value.departureBoard.departures

        #if DEBUG
        logRealtimeFieldsIfNeeded(stationID: stationID, departures: departures)
        #endif

        return departures
    }

    func fetchDepartures(
        forStationIDs stationIDs: [String],
        maxJourneys: Int = 20,
        filters: MultiDepartureFilters = .init()
    ) async throws -> [Departure] {
        let joined = stationIDs.joined(separator: "|")
        guard !joined.isEmpty else { return [] }

        var query: [URLQueryItem] = [
            URLQueryItem(name: "idList", value: joined),
            URLQueryItem(name: "maxJourneys", value: String(max(1, maxJourneys))),
            URLQueryItem(name: "rtMode", value: filters.rtMode),
            URLQueryItem(name: "type", value: filters.type)
        ]

        if !filters.operators.isEmpty {
            query.append(URLQueryItem(name: "operators", value: filters.operators.joined(separator: ",")))
        }
        if !filters.categories.isEmpty {
            query.append(URLQueryItem(name: "categories", value: filters.categories.joined(separator: ",")))
        }
        if !filters.lines.isEmpty {
            query.append(URLQueryItem(name: "lines", value: filters.lines.joined(separator: ",")))
        }
        if !filters.platforms.isEmpty {
            query.append(URLQueryItem(name: "platforms", value: filters.platforms.joined(separator: ",")))
        }
        if !filters.attributes.isEmpty {
            query.append(URLQueryItem(name: "attributes", value: filters.attributes.joined(separator: ",")))
        }
        if filters.passlist {
            query.append(URLQueryItem(name: "passlist", value: "1"))
        }

        let response: HafasResponse<DepartureBoardResponse> = try await client.request(
            service: .multiDepartureBoard,
            queryItems: query,
            context: HafasRequestContext(context: [
                "feature": "multiDepartureBoard",
                "stationCount": String(stationIDs.count)
            ])
        )

        return response.value.departureBoard.departures
    }

    func searchLocations(input: String) async throws -> [StationModel] {
        let normalizedInput = input.hasSuffix("?") ? input : input + "?"
        let response: HafasResponse<LocationNameResponse> = try await client.request(
            service: .locationName,
            queryItems: [
                URLQueryItem(name: "input", value: normalizedInput),
                URLQueryItem(name: "maxNo", value: "20")
            ],
            context: HafasRequestContext(context: [
                "feature": "locationName"
            ])
        )

        return response.value.stopLocations.map {
            StationModel(
                id: $0.id,
                extId: $0.extId,
                globalId: $0.globalId,
                name: $0.name,
                latitude: $0.latitude ?? 0,
                longitude: $0.longitude ?? 0,
                distanceMeters: $0.distanceMeters,
                type: $0.type,
                products: $0.products,
                productsBitmask: $0.productsBitmask,
                productAtStop: $0.productAtStop,
                category: $0.category,
                zone: $0.zone,
                zoneSource: $0.zoneSource,
                stationGroupId: $0.stationGroupId
            )
        }
    }

    func fetchJourneyDetail(id: String, date: String? = nil) async throws -> JourneyDetail {
        var queryWithDate: [URLQueryItem] = [
            // 按文档使用 `id` 参数（JourneyDetailRef.ref 的值）
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "showPassingPoints", value: "1")
        ]
        if let date, !date.isEmpty {
            queryWithDate.append(URLQueryItem(name: "date", value: date))
        }

        #if DEBUG
        if DebugFlags.realtimeFieldLoggingEnabled,
           let url = try? client.makeURL(service: .journeyDetail, queryItems: queryWithDate) {
            AppLogger.debug("[JDETAIL] requestURL=\(url.absoluteString)")
            let hasPartialParams = ["fromId", "fromIdx", "toId", "toIdx"].contains { key in
                url.absoluteString.contains("\(key)=")
            }
            AppLogger.debug("[JDETAIL] partialParamsPresent=\(hasPartialParams)")
        }
        #endif

        let firstResponse: HafasResponse<JourneyDetailResponse> = try await client.request(
            service: .journeyDetail,
            queryItems: queryWithDate,
            context: HafasRequestContext(context: [
                "feature": "journeyDetail"
            ])
        )
        let firstStops = firstResponse.value.journeyDetail.stops
        #if DEBUG
        if DebugFlags.realtimeFieldLoggingEnabled {
            AppLogger.debug("[JDETAIL] stopsCount=\(firstStops.count)")
        }
        #endif
        if firstStops.count >= 2 {
            return firstResponse.value.journeyDetail
        }

        // 回退 1：不传 date（部分部署在 date 格式不匹配时会返回空 stops）。
        let fallbackQuery: [URLQueryItem] = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "showPassingPoints", value: "1")
        ]
        #if DEBUG
        if DebugFlags.realtimeFieldLoggingEnabled,
           let url = try? client.makeURL(service: .journeyDetail, queryItems: fallbackQuery) {
            AppLogger.debug("[JDETAIL] fallbackRequestURL=\(url.absoluteString)")
        }
        #endif
        let fallbackResponse: HafasResponse<JourneyDetailResponse> = try await client.request(
            service: .journeyDetail,
            queryItems: fallbackQuery,
            context: HafasRequestContext(context: [
                "feature": "journeyDetail-fallback"
            ])
        )
        #if DEBUG
        if DebugFlags.realtimeFieldLoggingEnabled {
            AppLogger.debug("[JDETAIL] fallbackStopsCount=\(fallbackResponse.value.journeyDetail.stops.count)")
        }
        #endif
        if fallbackResponse.value.journeyDetail.stops.count >= 2 {
            return fallbackResponse.value.journeyDetail
        }

        // 回退 2：尝试去掉 journey id 中的区间边界（FR/FT/TO/TT），请求整趟线路。
        let normalizedID = normalizeJourneyIDForFullRoute(id)
        if normalizedID != id {
            let fullRouteQuery: [URLQueryItem] = [
                URLQueryItem(name: "id", value: normalizedID),
                URLQueryItem(name: "showPassingPoints", value: "1")
            ]
            #if DEBUG
            if DebugFlags.realtimeFieldLoggingEnabled,
               let url = try? client.makeURL(service: .journeyDetail, queryItems: fullRouteQuery) {
                AppLogger.debug("[JDETAIL] fullRouteRequestURL=\(url.absoluteString)")
            }
            #endif
            let fullRouteResponse: HafasResponse<JourneyDetailResponse> = try await client.request(
                service: .journeyDetail,
                queryItems: fullRouteQuery,
                context: HafasRequestContext(context: [
                    "feature": "journeyDetail-fullroute-fallback"
                ])
            )
            #if DEBUG
            if DebugFlags.realtimeFieldLoggingEnabled {
                AppLogger.debug("[JDETAIL] fullRouteStopsCount=\(fullRouteResponse.value.journeyDetail.stops.count)")
            }
            #endif
            if fullRouteResponse.value.journeyDetail.stops.count >= 2 {
                return fullRouteResponse.value.journeyDetail
            }
        }

        // 回退 3：从 journey id 提取起点/发车时刻，改查起点 departureBoard(passlist=1) 反推全程。
        if let expanded = try? await resolveFullRouteFromOriginBoard(journeyID: id),
           expanded.count >= 2 {
            #if DEBUG
            if DebugFlags.realtimeFieldLoggingEnabled {
                AppLogger.debug("[JDETAIL] originBoardStopsCount=\(expanded.count)")
            }
            #endif
            return JourneyDetail(stops: expanded)
        }

        return fallbackResponse.value.journeyDetail
    }

    private func normalizeJourneyIDForFullRoute(_ raw: String) -> String {
        var value = raw
        let patterns = [
            #"#FR#[^#]*"#,
            #"#FT#[^#]*"#,
            #"#TO#[^#]*"#,
            #"#TT#[^#]*"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "")
        }

        while value.contains("##") {
            value = value.replacingOccurrences(of: "##", with: "#")
        }
        return value
    }

    private func resolveFullRouteFromOriginBoard(journeyID: String) async throws -> [JourneyStop] {
        let tokens = journeyID.split(separator: "#").map(String.init)
        func value(after key: String) -> String? {
            guard let idx = tokens.firstIndex(of: key), idx + 1 < tokens.count else { return nil }
            return tokens[idx + 1]
        }

        guard
            let originID = value(after: "FR"),
            let timeToken = value(after: "FT"),
            let lineToken = value(after: "ZE")
        else {
            return []
        }

        let dateToken = value(after: "DA")
        let queryDate = normalizeJourneyDateToken(dateToken)
        let queryTime = normalizeJourneyTimeToken(timeToken)

        var query: [URLQueryItem] = [
            URLQueryItem(name: "id", value: originID),
            URLQueryItem(name: "time", value: queryTime),
            URLQueryItem(name: "duration", value: "240"),
            URLQueryItem(name: "maxJourneys", value: "60"),
            URLQueryItem(name: "passlist", value: "1"),
            URLQueryItem(name: "passlistMaxStops", value: "160"),
            URLQueryItem(name: "rtMode", value: "SERVER_DEFAULT"),
            URLQueryItem(name: "type", value: "DEP_EQUIVS")
        ]
        if let queryDate {
            query.append(URLQueryItem(name: "date", value: queryDate))
        }

        let response: HafasResponse<DepartureBoardResponse> = try await client.request(
            service: .departureBoard,
            queryItems: query,
            context: HafasRequestContext(context: [
                "feature": "journeyDetail-origin-board-fallback",
                "originId": originID
            ])
        )

        let targetToID = value(after: "TO")
        let candidates = response.value.departureBoard.departures.filter { dep in
            dep.name.contains(lineToken) || dep.name == lineToken
        }

        let ranked = candidates.sorted { lhs, rhs in
            lhs.passListStops.count > rhs.passListStops.count
        }

        for dep in ranked {
            if let targetToID, let lastID = dep.passListStops.last?.id {
                if lastID == targetToID, dep.passListStops.count >= 2 {
                    return dep.passListStops
                }
            } else if dep.passListStops.count >= 2 {
                return dep.passListStops
            }
        }

        return ranked.first?.passListStops ?? []
    }

    private func normalizeJourneyDateToken(_ token: String?) -> String? {
        guard let token, token.count == 6 else { return nil }
        let day = token.prefix(2)
        let month = token.dropFirst(2).prefix(2)
        let year = token.suffix(2)
        return "20\(year)-\(month)-\(day)"
    }

    private func normalizeJourneyTimeToken(_ token: String?) -> String {
        guard let token, token.count == 4 else { return "00:00" }
        let hour = token.prefix(2)
        let minute = token.suffix(2)
        return "\(hour):\(minute)"
    }
}

#if DEBUG
private extension RejseplanenAPIService {
    func logRealtimeFieldsIfNeeded(stationID: String, departures: [Departure]) {
        guard DebugFlags.realtimeFieldLoggingEnabled else { return }

        let total = departures.count
        let hasRealtimeCount = departures.filter { $0.hasRealtimeData }.count
        let withoutRealtimeCount = total - hasRealtimeCount
        AppLogger.debug("[RT-DEBUG] station=\(stationID) total=\(total) realtime=\(hasRealtimeCount) scheduleOnly=\(withoutRealtimeCount)")

        for (index, dep) in departures.prefix(25).enumerated() {
            let line = dep.name
            let type = dep.type
            let sched = "\(dep.date) \(dep.time)"
            let rt = "\(dep.rtDate ?? "-") \(dep.rtTime ?? "-")"
            let track = dep.track ?? "-"
            let rtTrack = dep.rtTrack ?? "-"
            let ref = dep.journeyRef ?? "-"
            AppLogger.debug("[RT-DEBUG] #\(index + 1) line=\(line) type=\(type) dir=\(dep.direction) sched=\(sched) rt=\(rt) track=\(track) rtTrack=\(rtTrack) hasRT=\(dep.hasRealtimeData) passlist=\(dep.passListStops.count) ref=\(ref)")
        }
    }
}
#endif

// MARK: - Nearby Stops DTO (Rejseplanen JSON)

/// `location.nearbystops?format=json` 根对象。
private struct NearbyStopsResponse: Decodable {
    let stopLocations: [StopLocation]

    enum CodingKeys: String, CodingKey {
        case locationList = "LocationList"
        case stopLocationOrCoordLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let locationList = try? container.decode(LocationList.self, forKey: .locationList) {
            stopLocations = locationList.stopLocations
            return
        }

        if let wrapped = try? container.decode([StopLocationWrapper].self, forKey: .stopLocationOrCoordLocation) {
            stopLocations = wrapped.compactMap { $0.stopLocation }
            return
        }

        stopLocations = []
    }
}

/// `LocationList` 容器。
private struct LocationList: Decodable {
    let stopLocations: [StopLocation]

    enum CodingKeys: String, CodingKey {
        case stopLocations = "StopLocation"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let list = try? container.decode([StopLocation].self, forKey: .stopLocations) {
            stopLocations = list
        } else if let single = try? container.decode(StopLocation.self, forKey: .stopLocations) {
            stopLocations = [single]
        } else {
            stopLocations = []
        }
    }

    init(stopLocations: [StopLocation]) {
        self.stopLocations = stopLocations
    }
}

/// API 2.0 常见返回：`stopLocationOrCoordLocation: [{ StopLocation: {...} }]`
private struct StopLocationWrapper: Decodable {
    let stopLocation: StopLocation?

    enum CodingKeys: String, CodingKey {
        case stopLocation = "StopLocation"
    }
}

/// 站点条目。
///
/// 常见字段：
/// - `x` / `y`：坐标，经常是放大 1_000_000 的整数。
/// - `id` / `name` / `dist`。
/// - `products`：bitmask 整数或字符串 token。
/// - `productAtStop`：产品详情数组（含 cls / catOut）。
private struct StopLocation: Decodable {
    let id: String
    let extId: String?
    let globalId: String?
    let name: String
    let longitude: Double?
    let latitude: Double?
    let distanceMeters: Double?
    let type: String?
    let products: [String]?
    let productsBitmask: Int?
    let productAtStop: [ProductAtStopEntry]?
    let category: String?
    let zone: String?
    let zoneSource: String
    let stationGroupId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case extId
        case globalId
        case name
        case x
        case y
        case lon
        case lat
        case dist
        case type
        case product
        case products
        case productAtStop
        case category
        case cat
        case zone
        case tariffZone
        case zoneNo
        case parent
        case parentId
        case groupId
        case stopGroup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let extID = try? container.decode(String.self, forKey: .extId) {
            id = extID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = ""
        }
        extId = try? container.decode(String.self, forKey: .extId)
        globalId = try? container.decode(String.self, forKey: .globalId)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown Stop"

        let rawX = Self.decodeFlexibleDouble(container: container, primary: .x, fallback: .lon)
        let rawY = Self.decodeFlexibleDouble(container: container, primary: .y, fallback: .lat)
        let rawDistance = Self.decodeFlexibleDouble(container: container, primary: .dist, fallback: .dist)

        longitude = rawX.map { Self.normalizeCoordinate($0, isLatitude: false) }
        latitude = rawY.map { Self.normalizeCoordinate($0, isLatitude: true) }
        distanceMeters = rawDistance
        type = try? container.decode(String.self, forKey: .type)

        // products: bitmask Int / String bitmask / String tokens / [String]
        let (decodedProducts, decodedBitmask) = Self.decodeProductsAndBitmask(container: container)
        products = decodedProducts
        productsBitmask = decodedBitmask

        // productAtStop: 数组或单对象
        if let list = try? container.decode([ProductAtStopEntry].self, forKey: .productAtStop) {
            productAtStop = list.isEmpty ? nil : list
        } else if let single = try? container.decode(ProductAtStopEntry.self, forKey: .productAtStop) {
            productAtStop = [single]
        } else {
            productAtStop = nil
        }

        category = (try? container.decode(String.self, forKey: .category))
            ?? (try? container.decode(String.self, forKey: .cat))
        let decodedZone = Self.decodeZone(container: container)
        zone = decodedZone.value
        zoneSource = decodedZone.source
        stationGroupId =
            (try? container.decode(String.self, forKey: .parent))
            ?? (try? container.decode(String.self, forKey: .parentId))
            ?? (try? container.decode(String.self, forKey: .groupId))
            ?? (try? container.decode(String.self, forKey: .stopGroup))
    }

    /// Rejseplanen 字段可能是字符串或数字，这里统一做宽松解码。
    private static func decodeFlexibleDouble(
        container: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        fallback: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: primary) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: primary), let value = Double(text) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: fallback) {
            return value
        }
        if let text = try? container.decode(String.self, forKey: fallback), let value = Double(text) {
            return value
        }
        return nil
    }

    /// 当坐标是微度（例如 `12568677`）时，缩放回标准经纬度。
    private static func normalizeCoordinate(_ value: Double, isLatitude: Bool) -> Double {
        let limit = isLatitude ? 90.0 : 180.0
        if abs(value) > limit {
            return value / 1_000_000.0
        }
        return value
    }

    /// 解码 products 字段：同时提取字符串 token 和 bitmask 整数。
    private static func decodeProductsAndBitmask(
        container: KeyedDecodingContainer<CodingKeys>
    ) -> (products: [String]?, bitmask: Int?) {
        // 1) 尝试直接解码为 Int（纯 bitmask）
        if let intValue = try? container.decode(Int.self, forKey: .products) {
            return (nil, intValue)
        }
        // 2) 尝试解码为 [String]
        if let list = try? container.decode([String].self, forKey: .products) {
            return (list, nil)
        }
        // 3) 尝试解码为 String
        if let raw = try? container.decode(String.self, forKey: .products) {
            if let intValue = Int(raw.trimmingCharacters(in: .whitespaces)) {
                return (nil, intValue)
            }
            let tokens = raw
                .split { $0 == "," || $0 == "|" || $0 == ";" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty { return (tokens, nil) }
        }
        // 4) 尝试 product（单数）字段
        if let raw = try? container.decode(String.self, forKey: .product) {
            if let intValue = Int(raw.trimmingCharacters(in: .whitespaces)) {
                return (nil, intValue)
            }
            return ([raw], nil)
        }
        return (nil, nil)
    }

    private static func decodeZone(
        container: KeyedDecodingContainer<CodingKeys>
    ) -> (value: String?, source: String) {
        if let text = try? container.decode(String.self, forKey: .zone) { return (text, "zone") }
        if let value = try? container.decode(Int.self, forKey: .zone) { return (String(value), "zoneInt") }
        if let text = try? container.decode(String.self, forKey: .tariffZone) { return (text, "tariffZone") }
        if let value = try? container.decode(Int.self, forKey: .tariffZone) { return (String(value), "tariffZoneInt") }
        if let text = try? container.decode(String.self, forKey: .zoneNo) { return (text, "zoneNo") }
        if let value = try? container.decode(Int.self, forKey: .zoneNo) { return (String(value), "zoneNoInt") }
        return (nil, "missing")
    }
}

private struct LocationNameResponse: Decodable {
    let stopLocations: [StopLocation]

    enum CodingKeys: String, CodingKey {
        case locationList = "LocationList"
        case stopLocationOrCoordLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let locationList = try? container.decode(LocationList.self, forKey: .locationList) {
            stopLocations = locationList.stopLocations
            return
        }

        if let wrapped = try? container.decode([StopLocationWrapper].self, forKey: .stopLocationOrCoordLocation) {
            stopLocations = wrapped.compactMap { $0.stopLocation }
            return
        }

        stopLocations = []
    }
}
