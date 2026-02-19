import Foundation

/// 产品类别缓存：从 `/datainfo` 获取 cls→Mode 映射，并提供 stop 产品 enrichment。
///
/// 设计：
/// - 启动时（或首次需要时）调用 `/datainfo` 缓存产品表。
/// - 对缺少 products 的 stop，用 `location.name` enrich 获取 StopLocation（含 products bitmask）。
/// - LRU/TTL 缓存（7 天），避免重复请求。
/// - 并发限制（最多 4 个同时 enrich 请求），避免 N+1 风暴。
actor ProductClassCache {
    static let shared = ProductClassCache()

    private var dataInfoLoaded = false
    private var enrichCache: [String: EnrichedStop] = [:]
    private var inflightEnrich: [String: Task<EnrichedStop?, Never>] = [:]
    private let maxConcurrentEnrich = 4
    private var activeEnrichCount = 0
    private let cacheTTL: TimeInterval = 7 * 24 * 3600 // 7 days

    struct EnrichedStop {
        let productsBitmask: Int?
        let productAtStop: [ProductAtStopEntry]?
        let timestamp: Date
    }

    // MARK: - DataInfo

    /// 从 `/datainfo` 加载产品类别映射并更新 TransportModeResolver。
    /// 仅在首次调用时执行网络请求，后续调用直接返回。
    func loadDataInfoIfNeeded(client: HafasClient) async {
        guard !dataInfoLoaded else { return }
        dataInfoLoaded = true // 防止重复请求（即使失败也不重试，用默认映射）

        do {
            let response: HafasResponse<DataInfoResponse> = try await client.request(
                service: .dataInfo,
                queryItems: [],
                context: HafasRequestContext(context: ["feature": "datainfo"])
            )

            var newMap: [Int: StationModel.StationMode.SingleMode] = [:]
            for product in response.value.products {
                guard let cls = product.cls, cls > 0 else { continue }
                let mode = inferModeFromDataInfoProduct(product)
                if let mode {
                    newMap[cls] = mode
                }
            }

            if !newMap.isEmpty {
                TransportModeResolver.updateClassMap(newMap)
                #if DEBUG
                print("[DataInfo] Updated product class map with \(newMap.count) entries: \(newMap)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[DataInfo] Failed to load datainfo, using defaults: \(error.localizedDescription)")
            #endif
        }
    }

    /// 从 datainfo product 条目推断 Mode。
    private func inferModeFromDataInfoProduct(_ product: DataInfoProduct) -> StationModel.StationMode.SingleMode? {
        let text = (product.catOutL ?? product.catOut ?? product.name ?? "").lowercased()
        if text.contains("bus") || text.contains("expresbus") || text.contains("fjernbus") { return .bus }
        if text.contains("metro") || text.contains("letbane") || text.contains("tram") { return .metro }
        if text.contains("tog") || text.contains("train") || text.contains("ic") || text.contains("re")
            || text.contains("s-tog") || text.contains("regional") { return .tog }
        // Ferry, walking, taxi → skip
        return nil
    }

    // MARK: - Stop Enrichment

    /// 对缺少 products 的 stop 进行 enrich（通过 location.name 查询）。
    /// 返回 enriched 的 productsBitmask 和 productAtStop，或 nil（如果无法 enrich）。
    func enrichStop(stopId: String, stopName: String, client: HafasClient) async -> EnrichedStop? {
        // 1) 检查缓存
        if let cached = enrichCache[stopId], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached
        }

        // 2) 检查是否已有 inflight 请求
        if let existing = inflightEnrich[stopId] {
            return await existing.value
        }

        // 3) 并发限制
        guard activeEnrichCount < maxConcurrentEnrich else {
            return nil // 超过并发限制，跳过（下次刷新时重试）
        }

        // 4) 发起请求
        activeEnrichCount += 1
        let task = Task<EnrichedStop?, Never> { [weak self] in
            defer {
                Task { await self?.decrementEnrichCount(stopId: stopId) }
            }

            do {
                let response: HafasResponse<LocationNameEnrichResponse> = try await client.request(
                    service: .locationName,
                    queryItems: [
                        URLQueryItem(name: "input", value: stopName),
                        URLQueryItem(name: "maxNo", value: "5")
                    ],
                    context: HafasRequestContext(context: ["feature": "enrichStop", "stopId": stopId])
                )

                // 找到匹配的 stop（优先精确 ID 匹配，否则名字匹配）
                let match = response.value.stops.first { $0.id == stopId }
                    ?? response.value.stops.first { $0.name.lowercased() == stopName.lowercased() }

                guard let match else { return nil }

                let enriched = EnrichedStop(
                    productsBitmask: match.productsBitmask,
                    productAtStop: match.productAtStop,
                    timestamp: Date()
                )
                await self?.cacheEnriched(stopId: stopId, value: enriched)
                return enriched
            } catch {
                #if DEBUG
                print("[Enrich] Failed for \(stopId) '\(stopName)': \(error.localizedDescription)")
                #endif
                return nil
            }
        }

        inflightEnrich[stopId] = task
        return await task.value
    }

    private func decrementEnrichCount(stopId: String) {
        activeEnrichCount = max(0, activeEnrichCount - 1)
        inflightEnrich[stopId] = nil
    }

    private func cacheEnriched(stopId: String, value: EnrichedStop) {
        enrichCache[stopId] = value
    }

    /// 清除过期缓存条目。
    func pruneExpiredCache() {
        let now = Date()
        enrichCache = enrichCache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
    }
}

// MARK: - DataInfo response models

struct DataInfoProduct: Decodable {
    let name: String?
    let catOut: String?
    let catOutL: String?
    let cls: Int?

    enum CodingKeys: String, CodingKey {
        case name, catOut, catOutL, cls
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decode(String.self, forKey: .name)
        catOut = try? container.decode(String.self, forKey: .catOut)
        catOutL = try? container.decode(String.self, forKey: .catOutL)
        if let intCls = try? container.decode(Int.self, forKey: .cls) {
            cls = intCls
        } else if let strCls = try? container.decode(String.self, forKey: .cls), let parsed = Int(strCls) {
            cls = parsed
        } else {
            cls = nil
        }
    }
}

struct DataInfoResponse: Decodable {
    let products: [DataInfoProduct]

    enum CodingKeys: String, CodingKey {
        case dataInfo = "DataInfo"
        case serviceInfo = "ServiceInfo"
        case product = "Product"
    }

    nonisolated init(from decoder: Decoder) throws {
        // DataInfo 响应格式多样，尝试多种路径
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 尝试 DataInfo.Product
        if let dataInfoContainer = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .dataInfo) {
            if let list = try? dataInfoContainer.decode([DataInfoProduct].self, forKey: .product) {
                products = list
                return
            }
            if let single = try? dataInfoContainer.decode(DataInfoProduct.self, forKey: .product) {
                products = [single]
                return
            }
        }

        // 尝试顶层 Product
        if let list = try? container.decode([DataInfoProduct].self, forKey: .product) {
            products = list
            return
        }

        products = []
    }
}

// MARK: - Enrich response (reuses StopLocation-like structure)

struct LocationNameEnrichResponse: Decodable {
    let stops: [EnrichStopLocation]

    enum CodingKeys: String, CodingKey {
        case locationList = "LocationList"
        case stopLocationOrCoordLocation
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let locationList = try? container.nestedContainer(keyedBy: LocationListKeys.self, forKey: .locationList) {
            if let list = try? locationList.decode([EnrichStopLocation].self, forKey: .stopLocation) {
                stops = list
                return
            }
            if let single = try? locationList.decode(EnrichStopLocation.self, forKey: .stopLocation) {
                stops = [single]
                return
            }
        }
        stops = []
    }

    enum LocationListKeys: String, CodingKey {
        case stopLocation = "StopLocation"
    }
}

struct EnrichStopLocation: Decodable {
    let id: String
    let name: String
    let productsBitmask: Int?
    let productAtStop: [ProductAtStopEntry]?

    enum CodingKeys: String, CodingKey {
        case id, name, products, productAtStop
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strId = try? container.decode(String.self, forKey: .id) {
            id = strId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = ""
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? ""

        // products bitmask
        if let intVal = try? container.decode(Int.self, forKey: .products) {
            productsBitmask = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .products),
                  let intVal = Int(strVal.trimmingCharacters(in: .whitespaces)) {
            productsBitmask = intVal
        } else {
            productsBitmask = nil
        }

        // productAtStop
        if let list = try? container.decode([ProductAtStopEntry].self, forKey: .productAtStop) {
            productAtStop = list.isEmpty ? nil : list
        } else if let single = try? container.decode(ProductAtStopEntry.self, forKey: .productAtStop) {
            productAtStop = [single]
        } else {
            productAtStop = nil
        }
    }
}
