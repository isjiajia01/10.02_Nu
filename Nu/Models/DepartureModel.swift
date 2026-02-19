import Foundation

/// 发车不确定性区间（单位：分钟）。
struct UncertaintyRange: Codable, Hashable {
    let lowerBound: Double
    let upperBound: Double
}

// MARK: - Root Response

/// Rejseplanen `departureBoard?format=json` 的根响应对象。
///
/// 示例：
/// {
///   "DepartureBoard": {
///      "Departure": [ ... ]
///   }
/// }
struct DepartureBoardResponse: Decodable {
    let departureBoard: DepartureBoard

    enum CodingKeys: String, CodingKey {
        case departureBoard = "DepartureBoard"
        case departureBoardLowercase = "departureBoard"
        case departures = "Departure"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let wrapped = try? container.decode(DepartureBoard.self, forKey: .departureBoard) {
            departureBoard = wrapped
            return
        }

        if let wrapped = try? container.decode(DepartureBoard.self, forKey: .departureBoardLowercase) {
            departureBoard = wrapped
            return
        }

        if let list = try? container.decode([Departure].self, forKey: .departures) {
            departureBoard = DepartureBoard(departures: list)
            return
        }

        if let single = try? container.decode(Departure.self, forKey: .departures) {
            departureBoard = DepartureBoard(departures: [single])
            return
        }

        departureBoard = DepartureBoard(departures: [])
    }

}

// MARK: - Departure Board Container

/// 发车板容器。
///
/// 注意：Rejseplanen 的 `Departure` 字段在不同场景可能表现为：
/// - 标准数组 `[Departure]`
/// - 单个对象 `Departure`
/// - 空或缺失
///
/// 因此这里使用自定义解码来做容错，避免线上因为结构波动导致解析失败。
struct DepartureBoard: Decodable {
    let departures: [Departure]

    enum CodingKeys: String, CodingKey {
        case departures = "Departure"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let list = try? container.decode([Departure].self, forKey: .departures) {
            departures = list
        } else if let single = try? container.decode(Departure.self, forKey: .departures) {
            departures = [single]
        } else {
            departures = []
        }
    }

    init(departures: [Departure]) {
        self.departures = departures
    }
}

// MARK: - Departure Item

/// 单条发车记录。
///
/// 字段说明：
/// - `time/date` 是计划时间。
/// - `rtTime/rtDate` 是实时更新后的时间，可能为空。
/// - `track/messages` 并非所有交通工具都有。
struct Departure: Codable, Identifiable, Hashable {
    /// API 不保证每条记录有稳定唯一 ID，因此使用关键字段组合生成。
    var id: String {
        journeyRef ?? (name + time + direction)
    }

    let journeyRef: String?
    let name: String
    let type: String
    let stop: String
    let time: String
    let date: String
    let rtTime: String?
    let rtDate: String?
    let direction: String
    let finalStop: String
    let track: String?
    let rtTrack: String?
    let messages: String?
    let passListStops: [JourneyStop]
    let uncertaintyRange: UncertaintyRange
    let reliabilityScore: Double
    let catchProbability: Double?
    let catchBucket: CatchBucket?

    enum CodingKeys: String, CodingKey {
        case name
        case line
        case type
        case product
        case cat
        case stop
        case time
        case date
        case rtTime
        case rtDate
        case direction
        case finalStop
        case track
        case rtTrack
        case messages
        case passList = "PassList"
        case passListLower = "passList"
        case stopsContainer = "Stops"
        case stopsContainerLower = "stops"
        case journeyStops = "JourneyStops"
        case journeyStopsLower = "journeyStops"
        case uncertaintyRange
        case uncertaintyLowerBound
        case uncertaintyUpperBound
        case reliabilityScore
        case catchProbability
        case catchBucket
        case journeyDetailRef = "JourneyDetailRef"
    }

    private struct JourneyDetailRef: Decodable {
        let ref: String?
    }

    init(
        journeyRef: String? = nil,
        name: String,
        type: String,
        stop: String,
        time: String,
        date: String,
        rtTime: String?,
        rtDate: String?,
        direction: String,
        finalStop: String,
        track: String?,
        rtTrack: String? = nil,
        messages: String?,
        passListStops: [JourneyStop] = [],
        uncertaintyRange: UncertaintyRange? = nil,
        reliabilityScore: Double = 0.6,
        catchProbability: Double? = nil,
        catchBucket: CatchBucket? = nil
    ) {
        self.journeyRef = journeyRef
        self.name = name
        self.type = type
        self.stop = stop
        self.time = time
        self.date = date
        self.rtTime = rtTime
        self.rtDate = rtDate
        self.direction = direction
        self.finalStop = finalStop
        self.track = track
        self.rtTrack = rtTrack
        self.messages = messages
        self.passListStops = passListStops
        self.uncertaintyRange = uncertaintyRange ?? Self.defaultUncertaintyRange(hasRealtime: rtTime != nil)
        self.reliabilityScore = min(max(reliabilityScore, 0), 1)
        self.catchProbability = catchProbability
        self.catchBucket = catchBucket
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawName = (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .line))
            ?? "Unknown"
        name = Self.normalizeLineName(rawName)

        let rawType = (try? container.decode(String.self, forKey: .type))
            ?? (try? container.decode(String.self, forKey: .product))
            ?? (try? container.decode(String.self, forKey: .cat))
            ?? ""
        type = Self.normalizeTransportType(rawType: rawType, lineName: name)
        stop = (try? container.decode(String.self, forKey: .stop)) ?? "Unknown Stop"
        time = (try? container.decode(String.self, forKey: .time)) ?? "--:--"
        date = (try? container.decode(String.self, forKey: .date)) ?? "01.01.70"
        rtTime = try? container.decode(String.self, forKey: .rtTime)
        rtDate = try? container.decode(String.self, forKey: .rtDate)
        direction = (try? container.decode(String.self, forKey: .direction))
            ?? (try? container.decode(String.self, forKey: .finalStop))
            ?? "-"
        finalStop = (try? container.decode(String.self, forKey: .finalStop)) ?? direction
        if let text = try? container.decode(String.self, forKey: .track) {
            track = text
        } else if let number = try? container.decode(Int.self, forKey: .track) {
            track = String(number)
        } else {
            track = nil
        }
        if let text = try? container.decode(String.self, forKey: .rtTrack) {
            rtTrack = text
        } else if let number = try? container.decode(Int.self, forKey: .rtTrack) {
            rtTrack = String(number)
        } else {
            rtTrack = nil
        }
        if let text = try? container.decode(String.self, forKey: .messages) {
            messages = text
        } else if let list = try? container.decode([String].self, forKey: .messages) {
            messages = list.joined(separator: " · ")
        } else {
            messages = nil
        }
        passListStops = Self.decodePassList(from: container)

        if let range = try? container.decode(UncertaintyRange.self, forKey: .uncertaintyRange) {
            uncertaintyRange = range
        } else {
            let lower = (try? container.decode(Double.self, forKey: .uncertaintyLowerBound))
            let upper = (try? container.decode(Double.self, forKey: .uncertaintyUpperBound))
            if let lower, let upper {
                uncertaintyRange = UncertaintyRange(lowerBound: lower, upperBound: upper)
            } else {
                uncertaintyRange = Self.defaultUncertaintyRange(hasRealtime: rtTime != nil)
            }
        }

        reliabilityScore = min(max((try? container.decode(Double.self, forKey: .reliabilityScore)) ?? 0.6, 0), 1)
        catchProbability = try? container.decode(Double.self, forKey: .catchProbability)
        if let decodedBucket = try? container.decode(CatchBucket.self, forKey: .catchBucket) {
            catchBucket = decodedBucket
        } else if let rawBucket = try? container.decode(String.self, forKey: .catchBucket) {
            catchBucket = CatchBucket(rawValue: rawBucket.lowercased())
        } else {
            catchBucket = nil
        }

        if let detailRef = try? container.decode(JourneyDetailRef.self, forKey: .journeyDetailRef) {
            journeyRef = detailRef.ref
        } else {
            journeyRef = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(stop, forKey: .stop)
        try container.encode(time, forKey: .time)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(rtTime, forKey: .rtTime)
        try container.encodeIfPresent(rtDate, forKey: .rtDate)
        try container.encode(direction, forKey: .direction)
        try container.encode(finalStop, forKey: .finalStop)
        try container.encodeIfPresent(track, forKey: .track)
        try container.encodeIfPresent(rtTrack, forKey: .rtTrack)
        try container.encodeIfPresent(messages, forKey: .messages)
        if !passListStops.isEmpty {
            try container.encode(PassListContainer(stops: passListStops), forKey: .passList)
        }
        try container.encode(uncertaintyRange, forKey: .uncertaintyRange)
        try container.encode(reliabilityScore, forKey: .reliabilityScore)
        try container.encodeIfPresent(catchProbability, forKey: .catchProbability)
        try container.encodeIfPresent(catchBucket, forKey: .catchBucket)
    }

    /// 是否晚点：当 `rtTime` 存在且与计划时间不同即视为晚点。
    var isDelayed: Bool {
        delayMinutes > 0
    }

    /// 是否存在任何实时字段。
    var hasRealtimeData: Bool {
        if let rtTime, !rtTime.isEmpty { return true }
        if let rtDate, !rtDate.isEmpty { return true }
        if let rtTrack, !rtTrack.isEmpty { return true }
        return false
    }

    /// 优先返回实时发车时间，否则返回计划时间。
    var effectiveTime: String {
        rtTime ?? time
    }

    /// The single source of truth for when this departure actually leaves.
    ///
    /// Priority:
    /// 1. Realtime date+time (rtTime + rtDate/date) if parseable
    /// 2. Scheduled date+time + delay offset (if delay is known but rt fields failed)
    /// 3. Scheduled date+time as last resort
    ///
    /// Returns `(date, isRealtime)`.
    var effectiveDepartureDate: (date: Date, isRealtime: Bool)? {
        // 1) Try realtime fields first
        if let rt = rtTime, !rt.isEmpty {
            if let parsed = parseDate(date: rtDate ?? date, time: rt) {
                return (parsed, true)
            }
        }
        // 2) Fallback: scheduled + delay (covers case where rtTime parsing fails
        //    but we know the delay from other signals)
        if let scheduled = parseDate(date: date, time: time) {
            if delayMinutes > 0 {
                let adjusted = scheduled.addingTimeInterval(Double(delayMinutes) * 60)
                return (adjusted, true)
            }
            return (scheduled, false)
        }
        return nil
    }

    /// 延误分钟数。无法计算时返回 0。
    var delayMinutes: Int {
        guard
            let realtime = parseDate(date: rtDate ?? date, time: effectiveTime),
            let scheduled = parseDate(date: date, time: time)
        else { return 0 }

        return max(Int(realtime.timeIntervalSince(scheduled) / 60), 0)
    }

    /// 距离发车的分钟数。无法解析时间时返回 `nil`。
    var minutesUntilDeparture: Int? {
        guard let target = parseDate(date: rtDate ?? date, time: effectiveTime) else { return nil }
        return max(Int(target.timeIntervalSinceNow / 60), 0)
    }

    /// 距离发车的原始分钟数（可能为负，表示已发车）。
    var minutesUntilDepartureRaw: Int? {
        guard let target = parseDate(date: rtDate ?? date, time: effectiveTime) else { return nil }
        return Int(target.timeIntervalSinceNow / 60)
    }

    /// VoiceOver 汇总文案。
    var accessibilitySummary: String {
        let minutesText = minutesUntilDeparture.map { L10n.tr("departures.accessibility.inMinutes", $0) } ?? L10n.tr("departures.accessibility.timePending")
        return L10n.tr("departures.accessibility.summary", name, direction, minutesText)
    }

    /// VoiceOver 状态值文案。
    var accessibilityStatus: String {
        if isDelayed {
            return L10n.tr("departures.accessibility.delayed", delayMinutes)
        }
        return L10n.tr("departures.accessibility.onTime")
    }

    private func parseDate(date: String, time: String) -> Date? {
        let zone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        let locale = Locale(identifier: "da_DK")
        let cleanDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time.trimmingCharacters(in: .whitespacesAndNewlines)

        let timeCandidates = Self.normalizeTimeCandidates(cleanTime)
        let dateCandidates = Self.normalizeDateCandidates(cleanDate)
        let dateTimeFormats = [
            "dd.MM.yy HH:mm",
            "dd.MM.yy HH:mm:ss",
            "dd.MM.yyyy HH:mm",
            "dd.MM.yyyy HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyyMMdd HH:mm",
            "yyyyMMdd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]

        for dateCandidate in dateCandidates {
            for timeCandidate in timeCandidates {
                for format in dateTimeFormats {
                    let formatter = DateFormatter()
                    formatter.locale = locale
                    formatter.timeZone = zone
                    formatter.dateFormat = format

                    let combined = "\(dateCandidate) \(timeCandidate)"
                    if let parsed = formatter.date(from: combined) {
                        return parsed
                    }
                    if let parsed = formatter.date(from: dateCandidate) {
                        return parsed
                    }
                }
            }
        }

        return Self.parseTimeOnly(cleanTime: cleanTime, zone: zone)
    }

    private static func defaultUncertaintyRange(hasRealtime: Bool) -> UncertaintyRange {
        if hasRealtime {
            // 启发式：有实时数据时，近似 N(0, 2)，取 P05/P95 区间。
            return UncertaintyRange(lowerBound: -3.29, upperBound: 3.29)
        }
        // 启发式：仅时刻表时，近似 U(0, 5)。
        return UncertaintyRange(lowerBound: 0.0, upperBound: 5.0)
    }

    private static func normalizeLineName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "Bus ", with: "")
            .replacingOccurrences(of: "Tog ", with: "")
            .replacingOccurrences(of: "Metro ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTransportType(rawType: String, lineName: String) -> String {
        let token = rawType.uppercased()
        let line = lineName.uppercased()

        if token.contains("METRO") || token == "M" || line.hasPrefix("M") {
            return "METRO"
        }
        if token.contains("BUS") || token == "EXB" || token == "NB" || token == "B" {
            return "BUS"
        }
        if token.contains("TRAM") || token == "LET" || token == "LRT" {
            return "TRAM"
        }
        if token.contains("FERRY") || token == "SHIP" || token == "BOAT" || token == "F" {
            return "FERRY"
        }
        if token.contains("TOG") || token.contains("TRAIN") || token == "IC" || token == "RE" || token == "S" {
            return "TOG"
        }

        if line.range(of: #"^\d+[A-Z]?$"#, options: .regularExpression) != nil {
            return "BUS"
        }
        if line.hasPrefix("M") {
            return "METRO"
        }

        return "TOG"
    }

    private static func normalizeDateCandidates(_ raw: String) -> [String] {
        if raw.isEmpty || raw == "-" || raw == "01.01.70" {
            return []
        }
        return [raw]
    }

    private static func normalizeTimeCandidates(_ raw: String) -> [String] {
        if raw.isEmpty || raw == "--:--" {
            return []
        }
        var values: [String] = [raw]
        if raw.count >= 5 {
            values.append(String(raw.prefix(5)))
        }
        return Array(Set(values))
    }

    private static func parseTimeOnly(cleanTime: String, zone: TimeZone) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = zone

        let formats = ["HH:mm:ss", "HH:mm"]
        for format in formats {
            formatter.dateFormat = format
            guard let parsedTime = formatter.date(from: cleanTime) else { continue }

            let now = Date()
            var components = calendar.dateComponents(in: zone, from: now)
            let timeComponents = calendar.dateComponents(in: zone, from: parsedTime)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = timeComponents.second ?? 0

            guard var candidate = calendar.date(from: components) else { continue }
            if candidate < now.addingTimeInterval(-3 * 3600) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
        return nil
    }

    private struct PassListContainer: Codable {
        let stops: [JourneyStop]

        enum CodingKeys: String, CodingKey {
            case stop = "Stop"
            case stopLower = "stop"
        }

        init(stops: [JourneyStop]) {
            self.stops = stops
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
            } else {
                stops = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stops, forKey: .stop)
        }
    }

    private static func decodePassList(from container: KeyedDecodingContainer<CodingKeys>) -> [JourneyStop] {
        if let value = try? container.decode(PassListContainer.self, forKey: .passList) {
            return value.stops
        }
        if let value = try? container.decode(PassListContainer.self, forKey: .passListLower) {
            return value.stops
        }
        if let value = try? container.decode(PassListContainer.self, forKey: .stopsContainer) {
            return value.stops
        }
        if let value = try? container.decode(PassListContainer.self, forKey: .stopsContainerLower) {
            return value.stops
        }
        if let value = try? container.decode(PassListContainer.self, forKey: .journeyStops) {
            return value.stops
        }
        if let value = try? container.decode(PassListContainer.self, forKey: .journeyStopsLower) {
            return value.stops
        }
        return []
    }
}
