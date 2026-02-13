import Foundation

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
}

struct MultiDepartureFilters {
    var operators: [String] = []
    var categories: [String] = []
    var lines: [String] = []
    var platforms: [String] = []
    var attributes: [String] = []
    var passlist: Bool = false
    var rtMode: String = "SERVER_DEFAULT"
    var type: String = "DEP_EQUIVS"
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
