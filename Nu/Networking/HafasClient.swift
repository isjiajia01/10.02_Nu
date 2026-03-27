import Foundation

nonisolated enum HafasServicePath: String {
    case nearbyStops = "location.nearbystops"
    case locationName = "location.name"
    case departureBoard = "departureBoard"
    case multiDepartureBoard = "multiDepartureBoard"
    case journeyDetail = "journeyDetail"
    case journeyPos = "journeypos"
    case trip = "trip"
    case dataInfo = "datainfo"
}

nonisolated struct HafasRequestContext: Sendable {
    let requestId: String
    let context: [String: String]

    nonisolated init(requestId: String = UUID().uuidString, context: [String: String] = [:]) {
        self.requestId = requestId
        self.context = context
    }
}

nonisolated private struct HafasResWrapper<T: Decodable>: Decodable {
    let res: T
}

nonisolated struct HafasWarningsContainer: Decodable {
    nonisolated struct Warning: Decodable, Hashable {
        let code: String?
        let text: String?
    }

    let warnings: [Warning]

    enum CodingKeys: String, CodingKey {
        case warnings = "Warnings"
        case warningsLower = "warnings"
    }

    nonisolated init(from decoder: Decoder) throws {
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

nonisolated enum HafasDecoder {
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder) throws -> T {
        if let direct = try? decoder.decode(T.self, from: data) {
            return direct
        }

        if let wrapped = try? decoder.decode(HafasResWrapper<T>.self, from: data) {
            return wrapped.res
        }

        return try decoder.decode(T.self, from: data)
    }
}

nonisolated struct HafasResponse<T: Decodable> {
    nonisolated let value: T
    nonisolated let warnings: [HafasWarningsContainer.Warning]
    nonisolated let requestId: String
    nonisolated let context: [String: String]
}

nonisolated enum HafasRequestBucket {
    case general
    case polling
}

nonisolated struct HafasRetryPolicy {
    let maxRetries: Int
    let initialDelaySeconds: TimeInterval
    let maxDelaySeconds: TimeInterval

    nonisolated static let standard = HafasRetryPolicy(maxRetries: 2, initialDelaySeconds: 0.5, maxDelaySeconds: 3)
    nonisolated static let polling = HafasRetryPolicy(maxRetries: 3, initialDelaySeconds: 0.5, maxDelaySeconds: 5)
    nonisolated static let disabled = HafasRetryPolicy(maxRetries: 0, initialDelaySeconds: 0, maxDelaySeconds: 0)
}

actor RequestRateLimiter {
    private let minInterval: TimeInterval
    private var lastRequestTime: Date = .distantPast

    init(minInterval: TimeInterval) {
        self.minInterval = max(0, minInterval)
    }

    func waitTurn() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minInterval {
            let wait = minInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}

nonisolated final class HafasClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let generalLimiter: RequestRateLimiter
    private let pollingLimiter: RequestRateLimiter

    nonisolated init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        self.generalLimiter = RequestRateLimiter(minInterval: AppConfig.generalMinRequestInterval)
        self.pollingLimiter = RequestRateLimiter(minInterval: AppConfig.pollingMinRequestInterval)
    }

    nonisolated func request<T: Decodable>(
        service: HafasServicePath,
        queryItems: [URLQueryItem],
        method: String = "GET",
        context: HafasRequestContext = HafasRequestContext(),
        bucket: HafasRequestBucket = .general,
        retryPolicy: HafasRetryPolicy = .standard
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
                let (value, warnings) = try await executeWithRetry(
                    request: request,
                    as: T.self,
                    context: context,
                    bucket: bucket,
                    retryPolicy: retryPolicy
                )
                #if DEBUG
                if !warnings.isEmpty {
                    AppLogger.debug("[HAFAS] requestId=\(context.requestId) warnings=\(warnings.map { $0.code ?? "-" }.joined(separator: ",")) context=\(context.context)")
                    let text = warnings.compactMap { $0.code ?? $0.text }.joined(separator: ", ")
                    Task { @MainActor in
                        AppDependencies.currentDiagnosticsStore.pushWarning("HAFAS Warnings: \(text)")
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

    private nonisolated func executeWithRetry<T: Decodable>(
        request: URLRequest,
        as type: T.Type,
        context: HafasRequestContext,
        bucket: HafasRequestBucket,
        retryPolicy: HafasRetryPolicy
    ) async throws -> (T, [HafasWarningsContainer.Warning]) {
        var attempt = 0
        var lastError: Error = APIError.unknown

        while attempt <= retryPolicy.maxRetries {
            await limiter(for: bucket).waitTurn()
            do {
                return try await execute(request: request, as: type, context: context)
            } catch {
                lastError = error
                guard shouldRetry(error: error, attempt: attempt, maxRetries: retryPolicy.maxRetries) else {
                    throw error
                }

                let delay = delayForRetry(
                    error: error,
                    attempt: attempt,
                    initialDelaySeconds: retryPolicy.initialDelaySeconds,
                    maxDelaySeconds: retryPolicy.maxDelaySeconds
                )
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                attempt += 1
            }
        }

        throw lastError
    }

    private nonisolated func limiter(for bucket: HafasRequestBucket) -> RequestRateLimiter {
        switch bucket {
        case .general:
            return generalLimiter
        case .polling:
            return pollingLimiter
        }
    }

    private nonisolated func shouldRetry(error: Error, attempt: Int, maxRetries: Int) -> Bool {
        guard attempt < maxRetries else { return false }
        guard let apiError = error as? APIError else { return false }
        switch apiError {
        case .rateLimited:
            return true
        case .network:
            return true
        case .httpStatus(let code):
            return code >= 500
        case .unauthorized, .forbidden:
            return false
        default:
            return false
        }
    }

    private nonisolated func delayForRetry(
        error: Error,
        attempt: Int,
        initialDelaySeconds: TimeInterval,
        maxDelaySeconds: TimeInterval
    ) -> TimeInterval {
        if case APIError.rateLimited(let retryAfter) = error,
           let retryAfter,
           retryAfter > 0 {
            return min(retryAfter, maxDelaySeconds)
        }

        let factor = pow(2.0, Double(attempt))
        return min(initialDelaySeconds * factor, maxDelaySeconds)
    }

    nonisolated func makeURL(service: HafasServicePath, queryItems: [URLQueryItem]) throws -> URL {
        try makeURLCandidates(service: service, queryItems: queryItems).first ?? {
            throw APIError.invalidRequest
        }()
    }

    private nonisolated func execute<T: Decodable>(
        request: URLRequest,
        as type: T.Type,
        context: HafasRequestContext
    ) async throws -> (T, [HafasWarningsContainer.Warning]) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                let retryAfter = Self.parseRetryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"))
                throw APIError.rateLimited(retryAfter: retryAfter)
            }
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 403 {
                throw APIError.forbidden
            }
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

    private nonisolated func extractServerText(from data: Data) -> String? {
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

    nonisolated private static func parseRetryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let date = formatter.date(from: trimmed) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private nonisolated func buildURL(base: URL, queryItems: [URLQueryItem]) -> URL? {
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

    nonisolated static func encodeQueryValue(_ value: String?) -> String? {
        guard let value else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "|")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private nonisolated func makeRequests(
        service: HafasServicePath,
        queryItems: [URLQueryItem],
        method: String,
        context: HafasRequestContext
    ) throws -> [URLRequest] {
        let urlCandidates = try makeURLCandidates(service: service, queryItems: queryItems)
        return urlCandidates.map { url in
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

    private nonisolated func makeURLCandidates(
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
