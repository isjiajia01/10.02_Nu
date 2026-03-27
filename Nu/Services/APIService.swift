import Foundation
import CoreLocation

/// API 服务协议（用于依赖注入）。
///
/// 设计目标：
/// - 通过协议隔离网络层，便于替换真实服务与 Mock 服务。
/// - 使用 async/await 统一异步调用风格。
protocol APIServiceProtocol {
    /// 获取附近站点。
    func fetchNearbyStops(
        coordX: Double,
        coordY: Double,
        radiusMeters: Int?,
        maxNo: Int?
    ) async throws -> [StationModel]

    /// 获取某个站点的发车信息。
    /// - Parameter stationID: 站点 ID。
    func fetchDepartures(for stationID: String) async throws -> [Departure]

    /// 多站聚合发车信息（multiDepartureBoard）。
    func fetchDepartures(
        forStationIDs stationIDs: [String],
        maxJourneys: Int,
        filters: MultiDepartureFilters
    ) async throws -> [Departure]

    /// 站点检索（`location.name`）。
    func searchLocations(input: String) async throws -> [StationModel]

    /// 行程详情（`journeyDetail`）。
    /// - Parameters:
    ///   - id: JourneyDetailRef 的 `ref` 值（按接口要求作为 `id` 传递）
    ///   - date: 可选运营日（yyyy-MM-dd）
    func fetchJourneyDetail(id: String, date: String?) async throws -> JourneyDetail

    /// 行程位置（`journeypos`）。
    func fetchJourneyPositions(
        bbox: JourneyPosBBox,
        filters: JourneyPosFilters,
        positionMode: JourneyPosMode
    ) async throws -> [JourneyVehicle]

    /// 解析追踪身份：优先 jid，失败则回退到 heuristic 键。
    func resolveTrackingIdentity(
        from departure: Departure,
        operationDate: String?
    ) async throws -> TrackingIdentity
}

/// 向后兼容：保留旧命名，避免其他文件立即大规模改动。
typealias APIService = APIServiceProtocol

extension APIServiceProtocol {
    func fetchNearbyStops(coordX: Double, coordY: Double) async throws -> [StationModel] {
        try await fetchNearbyStops(coordX: coordX, coordY: coordY, radiusMeters: nil, maxNo: nil)
    }

    func fetchDepartures(
        forStationIDs stationIDs: [String],
        maxJourneys: Int = 20,
        filters: MultiDepartureFilters = .init()
    ) async throws -> [Departure] {
        throw APIError.unknown
    }

    func searchLocations(input: String) async throws -> [StationModel] {
        throw APIError.unknown
    }

    func fetchJourneyDetail(id: String, date: String? = nil) async throws -> JourneyDetail {
        throw APIError.unknown
    }

    func fetchJourneyPositions(
        bbox: JourneyPosBBox,
        filters: JourneyPosFilters,
        positionMode: JourneyPosMode = .calcReport
    ) async throws -> [JourneyVehicle] {
        throw APIError.unknown
    }

    func resolveTrackingIdentity(
        from departure: Departure,
        operationDate: String? = nil
    ) async throws -> TrackingIdentity {
        let effective = departure.effectiveDepartureDate
        return TrackingIdentity(
            journeyRef: departure.journeyRef,
            jid: nil,
            line: departure.name,
            direction: departure.direction,
            plannedOrRealtimeDeparture: effective?.date
        )
    }
}

struct MultiDepartureFilters: Sendable {
    var operators: [String] = []
    var categories: [String] = []
    var lines: [String] = []
    var platforms: [String] = []
    var attributes: [String] = []
    var passlist: Bool = false
    var rtMode: String = "SERVER_DEFAULT"
    var type: String = "DEP_EQUIVS"

    nonisolated init(
        operators: [String] = [],
        categories: [String] = [],
        lines: [String] = [],
        platforms: [String] = [],
        attributes: [String] = [],
        passlist: Bool = false,
        rtMode: String = "SERVER_DEFAULT",
        type: String = "DEP_EQUIVS"
    ) {
        self.operators = operators
        self.categories = categories
        self.lines = lines
        self.platforms = platforms
        self.attributes = attributes
        self.passlist = passlist
        self.rtMode = rtMode
        self.type = type
    }
}

struct JourneyPosBBox: Sendable, Equatable {
    let llLat: Double
    let llLon: Double
    let urLat: Double
    let urLon: Double

    static func from(center: CLLocationCoordinate2D, spanLatitude: Double, spanLongitude: Double) -> [JourneyPosBBox] {
        let halfLat = max(0.0001, spanLatitude / 2.0)
        let halfLon = max(0.0001, spanLongitude / 2.0)

        let llLat = clampLatitude(center.latitude - halfLat)
        let urLat = clampLatitude(center.latitude + halfLat)
        var llLon = normalizeLongitude(center.longitude - halfLon)
        var urLon = normalizeLongitude(center.longitude + halfLon)

        if urLon < llLon {
            // Anti-meridian crossing: split into two boxes.
            return [
                JourneyPosBBox(llLat: llLat, llLon: llLon, urLat: urLat, urLon: 180),
                JourneyPosBBox(llLat: llLat, llLon: -180, urLat: urLat, urLon: urLon)
            ]
        }

        llLon = clampLongitude(llLon)
        urLon = clampLongitude(urLon)
        return [JourneyPosBBox(llLat: llLat, llLon: llLon, urLat: urLat, urLon: urLon)]
    }

    private static func clampLatitude(_ value: Double) -> Double {
        min(90, max(-90, value))
    }

    private static func clampLongitude(_ value: Double) -> Double {
        min(180, max(-180, value))
    }

    private static func normalizeLongitude(_ value: Double) -> Double {
        var v = value
        while v > 180 { v -= 360 }
        while v < -180 { v += 360 }
        return v
    }
}

struct JourneyPosFilters: Sendable, Equatable {
    var jid: String?
    var lines: [String] = []
    var operators: [String] = []
    var products: [String] = []

    nonisolated init(jid: String? = nil, lines: [String] = [], operators: [String] = [], products: [String] = []) {
        self.jid = jid
        self.lines = lines
        self.operators = operators
        self.products = products
    }
}

enum JourneyPosMode: String, Sendable {
    case reportOnly = "REPORT_ONLY"
    case calcReport = "CALC_REPORT"
    case calc = "CALC"
}

enum MatchConfidence: String, Sendable, Equatable {
    case exact
    case heuristic
}

struct TrackingIdentity: Sendable, Equatable {
    var journeyRef: String?
    var jid: String?
    var line: String?
    var direction: String?
    var plannedOrRealtimeDeparture: Date?
    var lastKnownCoordinate: CLLocationCoordinate2D?
    var lastMatchedVehicleId: String?
    var lastMatchAt: Date?
    var matchConfidence: MatchConfidence = .heuristic

    static func == (lhs: TrackingIdentity, rhs: TrackingIdentity) -> Bool {
        lhs.journeyRef == rhs.journeyRef
            && lhs.jid == rhs.jid
            && lhs.line == rhs.line
            && lhs.direction == rhs.direction
            && lhs.plannedOrRealtimeDeparture == rhs.plannedOrRealtimeDeparture
            && lhs.lastKnownCoordinate?.latitude == rhs.lastKnownCoordinate?.latitude
            && lhs.lastKnownCoordinate?.longitude == rhs.lastKnownCoordinate?.longitude
            && lhs.lastMatchedVehicleId == rhs.lastMatchedVehicleId
            && lhs.lastMatchAt == rhs.lastMatchAt
            && lhs.matchConfidence == rhs.matchConfidence
    }
}

struct JourneyVehicle: Sendable, Equatable, Identifiable {
    let id: String
    let jid: String?
    let journeyDetailRef: String?
    let line: String?
    let direction: String?
    let coordinate: CLLocationCoordinate2D
    let lastUpdated: Date?
    let isReportedPosition: Bool?
    let heading: Double?
    let stopName: String?
    let nextStopName: String?
    let originName: String?
    let destinationName: String?
    let productNumber: String?
    let productOperator: String?

    static func == (lhs: JourneyVehicle, rhs: JourneyVehicle) -> Bool {
        lhs.id == rhs.id
            && lhs.jid == rhs.jid
            && lhs.journeyDetailRef == rhs.journeyDetailRef
            && lhs.line == rhs.line
            && lhs.direction == rhs.direction
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.lastUpdated == rhs.lastUpdated
            && lhs.isReportedPosition == rhs.isReportedPosition
            && lhs.heading == rhs.heading
            && lhs.stopName == rhs.stopName
            && lhs.nextStopName == rhs.nextStopName
            && lhs.originName == rhs.originName
            && lhs.destinationName == rhs.destinationName
            && lhs.productNumber == rhs.productNumber
            && lhs.productOperator == rhs.productOperator
    }
}

/// 网络端点定义。
enum APIEndpoint {
    case nearbyStops(coordX: Double, coordY: Double)
    case departures(id: String)

    /// 接口路径。
    private var path: String {
        switch self {
        case .nearbyStops:
            return "location.nearbystops"
        case .departures:
            return "departureBoard"
        }
    }

    /// Query 参数。
    ///
    /// 注意：
    /// - `departureBoard` 强制加上 `format=json`，避免进入 XML 解析分支。
    private var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if AppConfig.hasAccessID {
            items.append(URLQueryItem(name: "accessId", value: AppConfig.accessID))
        }

        switch self {
        case .nearbyStops(let coordX, let coordY):
            let encodedX = Self.encodeCoordinateForNearbyStops(coordX, isLatitude: false)
            let encodedY = Self.encodeCoordinateForNearbyStops(coordY, isLatitude: true)
            items.append(contentsOf: [
                // API 2.0/HAFAS 常见参数（小数纬经度）
                URLQueryItem(name: "originCoordLong", value: String(coordX)),
                URLQueryItem(name: "originCoordLat", value: String(coordY)),
                // 兼容旧参数（微度）
                URLQueryItem(name: "coordX", value: encodedX),
                URLQueryItem(name: "coordY", value: encodedY),
                URLQueryItem(name: "maxNo", value: "30"),
                URLQueryItem(name: "format", value: "json")
            ])
            return items
        case .departures(let id):
            items.append(contentsOf: [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "useBus", value: "1"),
                URLQueryItem(name: "useTrain", value: "1"),
                URLQueryItem(name: "useMetro", value: "1"),
                URLQueryItem(name: "maxJourneys", value: "20"),
                URLQueryItem(name: "format", value: "json")
            ])
            return items
        }
    }

    /// `location.nearbystops` 兼容微度输入。
    /// - 若传入标准经纬度（绝对值在 90/180 以内），自动转成 *1_000_000 的整数。
    /// - 若上层已传微度，保持原值。
    private static func encodeCoordinateForNearbyStops(_ value: Double, isLatitude: Bool) -> String {
        let limit = isLatitude ? 90.0 : 180.0
        if abs(value) <= limit {
            return String(Int((value * 1_000_000.0).rounded()))
        }
        return String(Int(value.rounded()))
    }

    /// 构造完整 URLRequest。
    func makeRequest() throws -> URLRequest {
        guard let baseURL = AppConfig.baseURL else {
            throw APIError.invalidBaseURL
        }
        guard AppConfig.hasAccessID else {
            throw APIError.missingAccessID
        }

        let fullURL = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: fullURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }
}

/// 协议扩展：提供通用请求执行能力。
extension APIServiceProtocol {
    func performRequest<T: Decodable>(
        _ endpoint: APIEndpoint,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let request = try endpoint.makeRequest()

        do {
            return try await execute(request: request, session: session, decoder: decoder)
        } catch {
            // 自动重试一次，符合前期容错与弱网体验要求。
            return try await execute(request: request, session: session, decoder: decoder)
        }
    }

    /// 发请求、校验状态码、解码。
    private func execute<T: Decodable>(
        request: URLRequest,
        session: URLSession,
        decoder: JSONDecoder
    ) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let serverError = extractServerMessage(from: data) {
                    throw APIError.serverMessage("HTTP \(httpResponse.statusCode): \(serverError)")
                }
                throw APIError.httpStatus(httpResponse.statusCode)
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                if let serverError = extractServerMessage(from: data) {
                    throw APIError.serverMessage(serverError)
                }
                throw APIError.decodingFailed
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }

    private func extractServerMessage(from data: Data) -> String? {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String ?? object["errorText"] as? String
        {
            return error
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            if text.contains("<html") || text.contains("<!DOCTYPE html") {
                return L10n.tr("error.htmlResponse")
            }
            return String(text.prefix(160))
        }

        return nil
    }
}
