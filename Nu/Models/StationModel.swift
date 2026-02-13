import Foundation
import CoreLocation

/// 站点模型。
///
/// 说明：
/// - 字段设计保持轻量，优先满足附近站点列表和距离排序需求。
/// - `type` 用于 UI 快速区分 BUS / TOG / METRO。
struct StationModel: Codable, Identifiable, Hashable {
    let id: String
    let extId: String?
    let globalId: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?
    let type: String?
    let products: [String]?
    let category: String?
    let zone: String?
    let stationGroupId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case extId
        case globalId
        case name
        case latitude
        case longitude
        case lat
        case lon
        case x
        case y
        case distanceMeters
        case distance
        case dist
        case type
        case product
        case products
        case category
        case cat
        case zone
        case parent
        case parentId
        case groupId
        case stopGroup
    }

    init(
        id: String,
        extId: String? = nil,
        globalId: String? = nil,
        name: String,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double?,
        type: String?,
        products: [String]? = nil,
        category: String? = nil,
        zone: String? = nil,
        stationGroupId: String? = nil
    ) {
        self.id = id
        self.extId = extId
        self.globalId = globalId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.type = type
        self.products = products
        self.category = category
        self.zone = zone
        self.stationGroupId = stationGroupId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
            extId = try? container.decode(String.self, forKey: .extId)
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
            extId = try? container.decode(String.self, forKey: .extId)
        } else if let externalID = try? container.decode(String.self, forKey: .extId) {
            id = externalID
            extId = externalID
        } else {
            id = UUID().uuidString
            extId = nil
        }
        globalId = try? container.decode(String.self, forKey: .globalId)

        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown Stop"

        let rawLat = Self.decodeFlexibleDouble(container: container, keys: [.latitude, .lat, .y])
        let rawLon = Self.decodeFlexibleDouble(container: container, keys: [.longitude, .lon, .x])

        latitude = Self.normalize(rawLat ?? 0, isLatitude: true)
        longitude = Self.normalize(rawLon ?? 0, isLatitude: false)
        distanceMeters = Self.decodeFlexibleDouble(container: container, keys: [.distanceMeters, .distance, .dist])
        type = (try? container.decode(String.self, forKey: .type))
            ?? (try? container.decode(String.self, forKey: .product))
        products = Self.decodeProducts(container: container)
        category = (try? container.decode(String.self, forKey: .category))
            ?? (try? container.decode(String.self, forKey: .cat))
        zone = try? container.decode(String.self, forKey: .zone)
        stationGroupId =
            (try? container.decode(String.self, forKey: .parent))
            ?? (try? container.decode(String.self, forKey: .parentId))
            ?? (try? container.decode(String.self, forKey: .groupId))
            ?? (try? container.decode(String.self, forKey: .stopGroup))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(extId, forKey: .extId)
        try container.encodeIfPresent(globalId, forKey: .globalId)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(products, forKey: .products)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(zone, forKey: .zone)
        try container.encodeIfPresent(stationGroupId, forKey: .parent)
    }

    /// 供距离计算使用的 CoreLocation 对象。
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// VoiceOver 汇总文案。
    var accessibilitySummary: String {
        let distanceText = distanceMeters.map { L10n.tr("station.distance.meters", Int($0)) } ?? L10n.tr("station.distance.unknown")
        return L10n.tr("station.accessibility.summary", name, stationMode.detailLabel, distanceText)
    }

    /// VoiceOver 提示文案。
    var accessibilityHint: String {
        L10n.tr("station.accessibility.hint")
    }

    private static func decodeFlexibleDouble(
        container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Int.self, forKey: key) {
                return Double(value)
            }
            if let text = try? container.decode(String.self, forKey: key), let value = Double(text) {
                return value
            }
        }
        return nil
    }

    private static func normalize(_ value: Double, isLatitude: Bool) -> Double {
        let limit = isLatitude ? 90.0 : 180.0
        return abs(value) > limit ? (value / 1_000_000.0) : value
    }

    private static func decodeProducts(
        container: KeyedDecodingContainer<CodingKeys>
    ) -> [String]? {
        if let list = try? container.decode([String].self, forKey: .products) {
            return list
        }
        if let raw = try? container.decode(String.self, forKey: .products) {
            let tokens = raw
                .split { $0 == "," || $0 == "|" || $0 == ";" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty { return tokens }
        }
        if let raw = try? container.decode(String.self, forKey: .product) {
            return [raw]
        }
        return nil
    }
}

extension StationModel: StationTypeStylable {
    var stationType: String? { type }
}

/// 地图坐标扩展。
///
/// 说明：
/// - Rejseplanen 在部分接口里会返回“微度”整数（例如 `55676098`），
///   需要除以 `1_000_000` 才是标准纬度。
/// - 当前 `StationModel` 使用 `Double`，这里做一个兼容归一化：
///   如果数值超出正常经纬范围，则自动按微度缩放。
extension StationModel {
    enum StationMode: Hashable {
        case bus
        case metro
        case tog
        case mixed(Set<SingleMode>)
        case unknown

        enum SingleMode: String, Hashable {
            case bus = "BUS"
            case metro = "METRO"
            case tog = "TOG"
        }

        var primaryLabel: String {
            switch self {
            case .bus: return L10n.tr("mode.bus")
            case .metro: return L10n.tr("mode.metro")
            case .tog: return L10n.tr("mode.tog")
            case .mixed(let set):
                let text = set.map(\.rawValue).sorted().joined(separator: "·")
                return L10n.tr("mode.mixed", text)
            case .unknown: return L10n.tr("mode.bus")
            }
        }

        var detailLabel: String {
            switch self {
            case .bus: return L10n.tr("mode.bus")
            case .metro: return L10n.tr("mode.metro")
            case .tog: return L10n.tr("mode.tog")
            case .mixed(let set): return set.map(\.rawValue).sorted().joined(separator: " · ")
            case .unknown: return L10n.tr("mode.bus")
            }
        }
    }

    var stationMode: StationMode {
        let apiModes = detectedModesFromAPI()
        if apiModes.count >= 2 {
            return .mixed(apiModes)
        }
        if let single = apiModes.first {
            switch single {
            case .bus: return .bus
            case .metro: return .metro
            case .tog: return .tog
            }
        }

        let lower = name.lowercased()
        if lower.contains("(metro)") {
            return .metro
        }
        if lower.contains("stop") || lower.contains("stoppested") {
            return .bus
        }
        if lower.contains(" st.") || lower.contains(" station") || lower.contains(" tog") || lower.hasSuffix(" h") {
            return .tog
        }
        return .bus
    }

    var stationModeSubtitle: String {
        var parts: [String] = [stationMode.primaryLabel]
        if let zoneText = zone?.trimmingCharacters(in: .whitespacesAndNewlines), !zoneText.isEmpty {
            parts.append(L10n.tr("station.zone", zoneText))
        }
        if let distanceMeters {
            parts.append(L10n.tr("station.distance.metersShort", Int(distanceMeters)))
        }
        return parts.joined(separator: " · ")
    }

    var baseName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"\s*\([^)]*\)"#) else { return trimmed }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let cleaned = regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var entranceLabel: String {
        guard
            let start = name.firstIndex(of: "("),
            let end = name[name.index(after: start)...].firstIndex(of: ")"),
            start < end
        else {
            return baseName
        }
        let value = String(name[name.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? baseName : value
    }

    var modeMergeKey: String {
        switch stationMode {
        case .bus: return "BUS"
        case .metro: return "METRO"
        case .tog: return "TOG"
        case .mixed(let set): return "MIXED:\(set.map(\.rawValue).sorted().joined(separator: "|"))"
        case .unknown: return "UNKNOWN"
        }
    }

    private func detectedModesFromAPI() -> Set<StationMode.SingleMode> {
        let tokens: [String] = {
            var values: [String] = []
            if let type { values.append(type) }
            if let category { values.append(category) }
            if let products, !products.isEmpty { values.append(contentsOf: products) }
            return values
        }()

        var modes = Set<StationMode.SingleMode>()
        for token in tokens.map({ $0.uppercased() }) {
            if token.contains("BUS") { modes.insert(.bus) }
            if token.contains("METRO") || token == "M" || token.contains("TRAM") { modes.insert(.metro) }
            if token.contains("TOG") || token.contains("TRAIN") || token.contains("RAIL") || token == "S" || token == "IC" {
                modes.insert(.tog)
            }
        }
        return modes
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: normalize(latitude, isLatitude: true),
            longitude: normalize(longitude, isLatitude: false)
        )
    }

    private func normalize(_ value: Double, isLatitude: Bool) -> Double {
        let limit = isLatitude ? 90.0 : 180.0
        return abs(value) > limit ? (value / 1_000_000.0) : value
    }
}
