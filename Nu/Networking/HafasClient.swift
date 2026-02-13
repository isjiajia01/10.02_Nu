import Foundation

enum HafasServicePath: String {
    case nearbyStops = "location.nearbystops"
    case locationName = "location.name"
    case departureBoard = "departureBoard"
    case multiDepartureBoard = "multiDepartureBoard"
    case journeyDetail = "journeyDetail"
}

struct HafasRequestContext: Sendable {
    let requestId: String
    let context: [String: String]

    init(requestId: String = UUID().uuidString, context: [String: String] = [:]) {
        self.requestId = requestId
        self.context = context
    }
}

private struct HafasResWrapper<T: Decodable>: Decodable {
    let res: T
}

struct HafasWarningsContainer: Decodable {
    struct Warning: Decodable, Hashable {
        let code: String?
        let text: String?
    }

    let warnings: [Warning]

    enum CodingKeys: String, CodingKey {
        case warnings = "Warnings"
        case warningsLower = "warnings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decode([Warning].self, forKey: .warnings) {
            warnings = list
        } else if let list = try? container.decode([Warning].self, forKey: .warningsLower) {
            warnings = list
        } else {
            warnings = []
        }
    }
}

enum HafasDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T {
        if let direct = try? decoder.decode(T.self, from: data) {
            return direct
        }

        if let wrapped = try? decoder.decode(HafasResWrapper<T>.self, from: data) {
            return wrapped.res
        }

        return try decoder.decode(T.self, from: data)
    }
}

struct HafasResponse<T: Decodable> {
    let value: T
    let warnings: [HafasWarningsContainer.Warning]
    let requestId: String
    let context: [String: String]
}

final class HafasClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func request<T: Decodable>(
        service: HafasServicePath,
        queryItems: [URLQueryItem],
        method: String = "GET",
        context: HafasRequestContext = HafasRequestContext()
    ) async throws -> HafasResponse<T> {
        let requests = try makeRequests(
            service: service,
            queryItems: queryItems,
            method: method,
            context: context
        )

        var lastError: Error = APIError.unknown
        for request in requests {
            do {
                let (value, warnings) = try await execute(request: request, as: T.self, context: context)
                #if DEBUG
                if !warnings.isEmpty {
                    AppLogger.debug("[HAFAS] requestId=\(context.requestId) warnings=\(warnings.map { $0.code ?? "-" }.joined(separator: ",")) context=\(context.context)")
                    let text = warnings.compactMap { $0.code ?? $0.text }.joined(separator: ", ")
                    Task { @MainActor in
                        DiagnosticsStore.shared.pushWarning("HAFAS Warnings: \(text)")
                    }
                }
                #endif

                return HafasResponse(
                    value: value,
                    warnings: warnings,
                    requestId: context.requestId,
                    context: context.context
                )
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    func makeURL(service: HafasServicePath, queryItems: [URLQueryItem]) throws -> URL {
        try makeURLCandidates(service: service, queryItems: queryItems).first ?? {
            throw APIError.invalidRequest
        }()
    }

    private func execute<T: Decodable>(
        request: URLRequest,
        as type: T.Type,
        context: HafasRequestContext
    ) async throws -> (T, [HafasWarningsContainer.Warning]) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let text = extractServerText(from: data) {
                throw APIError.serverMessage("HTTP \(httpResponse.statusCode): \(text)")
            }
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        let value: T
        do {
            value = try HafasDecoder.decode(T.self, from: data, decoder: decoder)
        } catch {
            if let text = extractServerText(from: data) {
                throw APIError.serverMessage("Decode failed: \(text)")
            }
            throw APIError.decodingFailed
        }

        let warnings = (try? decoder.decode(HafasWarningsContainer.self, from: data).warnings) ?? []

        #if DEBUG
        if DebugFlags.realtimeFieldLoggingEnabled,
           context.context["feature"]?.contains("journeyDetail") == true {
            if let text = String(data: data, encoding: .utf8) {
                AppLogger.debug("[JDETAIL-RAW] \(String(text.prefix(800)))")
            }
        }
        #endif
        return (value, warnings)
    }

    private func extractServerText(from data: Data) -> String? {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["error"] as? String
                ?? object["errorText"] as? String
                ?? object["message"] as? String
        {
            return String(message.prefix(220))
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return String(text.prefix(220))
        }

        return nil
    }

    private func buildURL(base: URL, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.percentEncodedQueryItems = queryItems.map {
            URLQueryItem(
                name: $0.name,
                value: Self.encodeQueryValue($0.value)
            )
        }
        return components.url
    }

    static func encodeQueryValue(_ value: String?) -> String? {
        guard let value else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "|")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private func makeRequests(
        service: HafasServicePath,
        queryItems: [URLQueryItem],
        method: String,
        context: HafasRequestContext
    ) throws -> [URLRequest] {
        let urlCandidates = try makeURLCandidates(service: service, queryItems: queryItems)
        return try urlCandidates.map { url in
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(context.requestId, forHTTPHeaderField: "X-Request-ID")
            if let token = AppConfig.authorizationBearerToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return request
        }
    }

    private func makeURLCandidates(
        service: HafasServicePath,
        queryItems: [URLQueryItem]
    ) throws -> [URL] {
        guard let baseURL = AppConfig.baseURL else {
            throw APIError.invalidBaseURL
        }

        var items = queryItems
        if AppConfig.hasAccessID {
            items.append(URLQueryItem(name: "accessId", value: AppConfig.accessID))
        } else {
            throw APIError.missingAccessID
        }
        if items.contains(where: { $0.name == "format" }) == false {
            items.append(URLQueryItem(name: "format", value: "json"))
        }

        var candidates: [URL] = []
        let version = AppConfig.apiVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !version.isEmpty {
            let versioned = baseURL.appendingPathComponent("\(version)/\(service.rawValue)")
            if let url = buildURL(base: versioned, queryItems: items) {
                candidates.append(url)
            }
        }

        let unversioned = baseURL.appendingPathComponent(service.rawValue)
        if let url = buildURL(base: unversioned, queryItems: items) {
            candidates.append(url)
        }

        if candidates.isEmpty {
            throw APIError.invalidRequest
        }
        return candidates
    }
}

enum DeparturePaging {
    static func nextPageTime(from departures: [Departure], timeZone: TimeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current) -> String? {
        guard let last = departures.max(by: { ($0.minutesUntilDepartureRaw ?? .min) < ($1.minutesUntilDepartureRaw ?? .min) }),
              let target = last.minutesUntilDepartureRaw else {
            return nil
        }

        let next = Date().addingTimeInterval(TimeInterval((target + 1) * 60))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: next)
    }
}
