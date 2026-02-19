import Foundation

// MARK: - ProductAtStop entry (HAFAS productAtStop array element)

/// HAFAS `productAtStop` 条目，包含线路名、产品类别、cls 等。
struct ProductAtStopEntry: Codable, Hashable {
    let name: String?
    let catOut: String?
    let catOutS: String?
    let catOutL: String?
    let cls: Int?

    enum CodingKeys: String, CodingKey {
        case name, catOut, catOutS, catOutL, cls
    }

    init(name: String? = nil, catOut: String? = nil, catOutS: String? = nil, catOutL: String? = nil, cls: Int? = nil) {
        self.name = name
        self.catOut = catOut
        self.catOutS = catOutS
        self.catOutL = catOutL
        self.cls = cls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decode(String.self, forKey: .name)
        catOut = try? container.decode(String.self, forKey: .catOut)
        catOutS = try? container.decode(String.self, forKey: .catOutS)
        catOutL = try? container.decode(String.self, forKey: .catOutL)
        // cls 可能是 Int 或 String
        if let intCls = try? container.decode(Int.self, forKey: .cls) {
            cls = intCls
        } else if let strCls = try? container.decode(String.self, forKey: .cls), let parsed = Int(strCls) {
            cls = parsed
        } else {
            cls = nil
        }
    }
}

// MARK: - TransportModeResolver

/// 交通模式解析器（单一入口）。
///
/// 解析优先级：
/// 1. `productAtStop` 数组（catOut / cls 字段）
/// 2. `products` bitmask（整数）
/// 3. `products` 字符串 token（"BUS"/"METRO" 等）
/// 4. `type` 显式交通类型（仅 BUS / METRO / TOG）
/// 5. 站名兜底（仅 "(Metro)" / "(S-tog)"）
/// 6. `.unknown`
///
/// 重要：`stop.type`（"ST"/"ADR"/"POI"）是地点类型，绝不参与 mode 推断。
enum TransportModeResolver {

    typealias SingleMode = StationModel.StationMode.SingleMode

    // MARK: - Product class mapping (Rejseplanen / HAFAS)

    /// cls → Mode 映射表。启动时可通过 `/datainfo` 更新。
    /// 默认值基于 Rejseplanen Copenhagen 实际数据。
    ///
    /// Rejseplanen 常见 cls 值：
    /// - 1: ICE/IC 长途列车 → tog
    /// - 2: IC 城际列车 → tog
    /// - 4: RE/RB 区域列车 → tog
    /// - 8: S-tog → tog
    /// - 16: Bus → bus
    /// - 32: Expresbus / Fjernbus → bus
    /// - 64: Metro → metro
    /// - 128: Letbane（轻轨）→ metro
    /// - 256: Ferry → (skip)
    /// - 512: Walking → (skip)
    /// - 1024: Taxi → (skip)
    nonisolated(unsafe) private(set) static var productClassMap: [Int: SingleMode] = defaultProductClassMap

    nonisolated static let defaultProductClassMap: [Int: SingleMode] = [
        1: .tog, 2: .tog, 4: .tog, 8: .tog,
        16: .bus, 32: .bus,
        64: .metro, 128: .metro
    ]

    /// 用 `/datainfo` 返回的数据更新映射表。
    nonisolated static func updateClassMap(_ newMap: [Int: SingleMode]) {
        productClassMap = newMap
    }

    /// 重置为默认映射（测试用）。
    nonisolated static func resetToDefaults() {
        productClassMap = defaultProductClassMap
    }

    // MARK: - Public resolve

    /// 从所有可用字段解析交通模式集合。
    ///
    /// - Parameters:
    ///   - productAtStop: HAFAS productAtStop 数组（优先级最高）
    ///   - productsBitmask: products 整数 bitmask
    ///   - productTokens: products 字符串 token（"BUS"/"Metro" 等，来自 category 或旧格式 products）
    ///   - stationName: 站名（仅用于最后兜底）
    ///   - stopId: 用于 debug 日志
    ///   - stopType: 原始 type 字段（仅用于 debug 日志，不参与推断）
    /// - Returns: 解析出的模式集合和来源标识
    nonisolated static func resolve(
        productAtStop: [ProductAtStopEntry]?,
        productsBitmask: Int?,
        productTokens: [String]?,
        stationName: String,
        stopId: String = "",
        stopType: String? = nil
    ) -> (modes: Set<SingleMode>, source: String) {

        // 1) productAtStop（最高优先级）
        if let entries = productAtStop, !entries.isEmpty {
            let modes = modesFromProductAtStop(entries)
            if !modes.isEmpty {
                debugLog(id: stopId, name: stationName, type: stopType, bitmask: productsBitmask, tokens: productTokens, entries: entries, modes: modes, source: "productAtStop")
                return (modes, "productAtStop")
            }
        }

        // 2) products bitmask
        if let bitmask = productsBitmask, bitmask > 0 {
            let modes = modesFromBitmask(bitmask)
            if !modes.isEmpty {
                debugLog(id: stopId, name: stationName, type: stopType, bitmask: bitmask, tokens: productTokens, entries: nil, modes: modes, source: "bitmask(\(bitmask))")
                return (modes, "bitmask")
            }
        }

        // 3) 字符串 token（category 或旧格式 products）
        if let tokens = productTokens, !tokens.isEmpty {
            let modes = modesFromStringTokens(tokens)
            if !modes.isEmpty {
                debugLog(id: stopId, name: stationName, type: stopType, bitmask: productsBitmask, tokens: tokens, entries: nil, modes: modes, source: "stringTokens")
                return (modes, "stringTokens")
            }
        }

        // 4) type 显式映射（仅 BUS / METRO / TOG）
        let typeModes = modesFromExplicitType(stopType)
        if !typeModes.isEmpty {
            debugLog(id: stopId, name: stationName, type: stopType, bitmask: productsBitmask, tokens: productTokens, entries: nil, modes: typeModes, source: "typeMapping")
            return (typeModes, "typeMapping")
        }

        // 5) 站名兜底（仅极少数明确标识）
        let nameModes = modesFromNameFallback(stationName)
        if !nameModes.isEmpty {
            debugLog(id: stopId, name: stationName, type: stopType, bitmask: productsBitmask, tokens: productTokens, entries: nil, modes: nameModes, source: "nameFallback")
            return (nameModes, "nameFallback")
        }

        // 6) unknown
        debugLog(id: stopId, name: stationName, type: stopType, bitmask: productsBitmask, tokens: productTokens, entries: nil, modes: [], source: "unknown")
        return ([], "unknown")
    }

    // MARK: - Bitmask decoding

    /// 从 products bitmask 解码交通模式。
    nonisolated static func modesFromBitmask(_ bitmask: Int) -> Set<SingleMode> {
        var modes = Set<SingleMode>()
        for (cls, mode) in productClassMap {
            if bitmask & cls != 0 {
                modes.insert(mode)
            }
        }
        return modes
    }

    // MARK: - productAtStop decoding

    /// 从 productAtStop 条目解码交通模式。
    nonisolated static func modesFromProductAtStop(_ entries: [ProductAtStopEntry]) -> Set<SingleMode> {
        var modes = Set<SingleMode>()
        for entry in entries {
            // 优先用 cls
            if let cls = entry.cls, let mode = productClassMap[cls] {
                modes.insert(mode)
                continue
            }
            // 回退到 catOut / catOutL 文本匹配
            let text = (entry.catOut ?? entry.catOutL ?? entry.catOutS ?? "").uppercased()
            if text.isEmpty { continue }
            if text.contains("BUS") || text.contains("EXPRESBUS") { modes.insert(.bus) }
            else if text.contains("METRO") || text.contains("TRAM") || text.contains("LETBANE") || text.contains("LET") { modes.insert(.metro) }
            else if text.contains("TOG") || text.contains("TRAIN") || text.contains("S-TOG") || text.contains("IC") || text.contains("RE") { modes.insert(.tog) }
        }
        return modes
    }

    // MARK: - String token matching

    /// 从字符串 token 匹配交通模式（兼容旧格式 products 和 category）。
    nonisolated static func modesFromStringTokens(_ tokens: [String]) -> Set<SingleMode> {
        var modes = Set<SingleMode>()
        for token in tokens.map({ $0.uppercased() }) {
            // 先尝试解析为 bitmask 整数
            if let intValue = Int(token), intValue > 0 {
                modes.formUnion(modesFromBitmask(intValue))
                continue
            }
            // 字符串关键字匹配
            if token.contains("BUS") { modes.insert(.bus) }
            if token.contains("METRO") || token == "M" || token.contains("TRAM") || token == "LET" { modes.insert(.metro) }
            if token.contains("TOG") || token.contains("TRAIN") || token.contains("RAIL")
                || token == "S" || token == "IC" || token == "ICL" || token == "EC"
                || token == "RE" || token == "REG" {
                modes.insert(.tog)
            }
        }
        return modes
    }

    // MARK: - Name fallback (controlled)

    /// 站名兜底：仅允许极少数明确标识。
    /// 绝对禁止用 "St." 推断 TOG。
    nonisolated static func modesFromNameFallback(_ name: String) -> Set<SingleMode> {
        let lower = name.lowercased()
        if lower.contains("(metro)") { return [.metro] }
        if lower.contains("(s-tog)") || lower.contains("(s\u{2011}tog)") { return [.tog] }
        return []
    }

    nonisolated static func modesFromExplicitType(_ type: String?) -> Set<SingleMode> {
        guard let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return []
        }
        switch raw {
        case "BUS":
            return [.bus]
        case "METRO":
            return [.metro]
        case "TOG", "TRAIN", "RAIL":
            return [.tog]
        default:
            return []
        }
    }

    // MARK: - Debug logging

    private nonisolated static func debugLog(
        id: String, name: String, type: String?,
        bitmask: Int?, tokens: [String]?,
        entries: [ProductAtStopEntry]?, modes: Set<SingleMode>, source: String
    ) {
        #if DEBUG
        let modeStr = modes.isEmpty ? "∅" : modes.map(\.rawValue).sorted().joined(separator: ",")
        let bitmaskStr = bitmask.map { String($0) } ?? "nil"
        let tokenStr = tokens?.joined(separator: ",") ?? "nil"
        let entryCount = entries?.count ?? 0
        print("[ModeDebug] id=\(id) name=\"\(name)\" type=\(type ?? "nil") bitmask=\(bitmaskStr) tokens=[\(tokenStr)] productAtStop=\(entryCount)entries → modes={\(modeStr)} source=\(source)")
        #endif
    }
}
