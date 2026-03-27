import Foundation
import CoreLocation

/// 站点模型。
///
/// 说明：
/// - 字段设计保持轻量，优先满足附近站点列表和距离排序需求。
/// - `type` 是 HAFAS 地点类型（"ST"/"ADR"/"POI"），不用于交通模式推断。
/// - 交通模式来自 `productsBitmask` / `productAtStop` / `products` token。
nonisolated struct StationModel: Codable, Identifiable, Hashable {
    let id: String
    let extId: String?
    let globalId: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double?
    let type: String?
    let products: [String]?
    let productsBitmask: Int?
    let productAtStop: [ProductAtStopEntry]?
    let category: String?
    let zone: String?
    let zoneSource: String
    let stationGroupId: String?

    nonisolated enum CodingKeys: String, CodingKey {
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
        case productsBitmask
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
        productsBitmask: Int? = nil,
        productAtStop: [ProductAtStopEntry]? = nil,
        category: String? = nil,
        zone: String? = nil,
        zoneSource: String = "manual",
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
        self.productsBitmask = productsBitmask
        self.productAtStop = productAtStop
        self.category = category
        self.zone = zone
        self.zoneSource = zoneSource
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

        // products: 尝试解码为 bitmask Int、String token 数组、或单个 product 字符串
        let (decodedProducts, decodedBitmask) = Self.decodeProductsAndBitmask(container: container)
        products = decodedProducts
        productsBitmask = decodedBitmask

        // productAtStop: 数组或单对象
        productAtStop = Self.decodeProductAtStop(container: container)

        category = (try? container.decode(String.self, forKey: .category))
            ?? (try? container.decode(String.self, forKey: .cat))
        let decodedZone = Self.decodeZoneWithSource(container: container)
        zone = decodedZone.value
        zoneSource = decodedZone.source
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
        try container.encodeIfPresent(productsBitmask, forKey: .productsBitmask)
        try container.encodeIfPresent(productAtStop, forKey: .productAtStop)
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

    /// 解码 products 字段：同时提取字符串 token 和 bitmask 整数。
    ///
    /// HAFAS 返回格式多样：
    /// - `"products": 128`（整数 bitmask）
    /// - `"products": "128"`（字符串形式的 bitmask）
    /// - `"products": "BUS,Metro"`（逗号分隔的 token）
    /// - `"products": ["BUS","Metro"]`（数组）
    /// - `"product": "BUS"`（单个 product 字段）
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
            // 如果是纯数字 → bitmask
            if let intValue = Int(raw.trimmingCharacters(in: .whitespaces)) {
                return (nil, intValue)
            }
            // 否则按分隔符拆分为 token
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

        // 5) 尝试从缓存字段 productsBitmask 读取（我们自己 encode 的）
        if let cached = try? container.decode(Int.self, forKey: .productsBitmask) {
            return (nil, cached)
        }

        return (nil, nil)
    }

    /// 解码 productAtStop 字段（数组或单对象）。
    private static func decodeProductAtStop(
        container: KeyedDecodingContainer<CodingKeys>
    ) -> [ProductAtStopEntry]? {
        if let list = try? container.decode([ProductAtStopEntry].self, forKey: .productAtStop) {
            return list.isEmpty ? nil : list
        }
        if let single = try? container.decode(ProductAtStopEntry.self, forKey: .productAtStop) {
            return [single]
        }
        return nil
    }

    private static func decodeZoneWithSource(
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

extension StationModel: StationTypeStylable {
    /// 从 stationMode 派生，确保与 StationModeVisualStyle 一致。
    /// 不再直接使用 raw type 字段（"ST"/"ADR" 等不是交通方式）。
    var stationType: String? {
        switch stationMode {
        case .bus: return "BUS"
        case .metro: return "METRO"
        case .tog: return "TOG"
        case .mixed: return "METRO" // mixed 场景用最高优先级 mode 做图标
        case .unknown: return nil
        }
    }
}

/// 地图坐标扩展。
///
/// 说明：
/// - Rejseplanen 在部分接口里会返回“微度”整数（例如 `55676098`），
///   需要除以 `1_000_000` 才是标准纬度。
/// - 当前 `StationModel` 使用 `Double`，这里做一个兼容归一化：
///   如果数值超出正常经纬范围，则自动按微度缩放。
extension StationModel {
    struct ModeResolution: Hashable {
        let modes: Set<StationMode.SingleMode>
        let source: String

        var reason: String {
            switch source {
            case "productAtStop", "bitmask", "stringTokens":
                return "apiProducts"
            case "typeMapping":
                return "typeMapping"
            case "nameFallback":
                return "nameFallback"
            default:
                return "unknown"
            }
        }
    }

    nonisolated enum StationMode: Hashable {
        case bus
        case metro
        case tog
        case mixed(Set<SingleMode>)
        case unknown

        nonisolated enum SingleMode: String, Hashable {
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
            case .unknown: return L10n.tr("mode.unknown")
            }
        }

        var detailLabel: String {
            switch self {
            case .bus: return L10n.tr("mode.bus")
            case .metro: return L10n.tr("mode.metro")
            case .tog: return L10n.tr("mode.tog")
            case .mixed(let set): return set.map(\.rawValue).sorted().joined(separator: " · ")
            case .unknown: return L10n.tr("mode.unknown")
            }
        }
    }

    var modeResolution: ModeResolution {
        // 构建 category token（不含 type，type 是地点类型）
        var tokens: [String] = []
        if let category { tokens.append(category) }
        if let products, !products.isEmpty { tokens.append(contentsOf: products) }

        let (resolved, source) = TransportModeResolver.resolve(
            productAtStop: productAtStop,
            productsBitmask: productsBitmask,
            productTokens: tokens.isEmpty ? nil : tokens,
            stationName: name,
            stopId: id,
            stopType: type
        )
        return ModeResolution(modes: resolved, source: source)
    }

    var stationMode: StationMode {
        let resolved = modeResolution.modes

        if resolved.count >= 2 { return .mixed(resolved) }
        if let single = resolved.first {
            switch single {
            case .bus: return .bus
            case .metro: return .metro
            case .tog: return .tog
            }
        }
        return .unknown
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
