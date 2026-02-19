import Foundation
import Combine
import SwiftUI

/// 收藏站点实体。
struct FavoriteStation: Codable, Identifiable, Hashable {
    let id: String
    let extId: String?
    let globalId: String?
    let name: String
    let type: String?
}

extension FavoriteStation: StationTypeStylable {
    var stationType: String? {
        if let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let upper = raw.uppercased()
            // 只接受已知的交通方式值；"ST"/"ADR"/"POI" 等地点类型不是交通方式
            if ["BUS", "METRO", "TOG"].contains(upper) {
                return upper
            }
        }

        // 历史收藏可能没有保存 type，做轻量推断。
        // 仅允许明确的名字标识，禁止用 "St." 推断 TOG。
        let lower = name.lowercased()
        if lower.contains("(metro)") || lower.contains("metro") { return "METRO" }
        if lower.contains("(s-tog)") || lower.contains("(s‑tog)") { return "TOG" }
        if lower.contains("bus") { return "BUS" }
        return nil
    }
}

/// 收藏管理器。
///
/// 说明：
/// - 使用单例保证全 App 共享同一份收藏状态。
/// - 使用 `UserDefaults` 做轻量持久化，满足站点收藏需求。
final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager(storage: UserDefaults.standard)

    /// 已收藏站点列表。
    @Published var savedStations: [FavoriteStation] = []

    private let key = "saved_stations"
    private let storage: KeyValueStoring

    init(storage: KeyValueStoring) {
        self.storage = storage
        loadFavorites()
    }

    /// 切换收藏状态：已收藏则移除，未收藏则添加。
    func toggleFavorite(
        stationId: String,
        extId: String? = nil,
        globalId: String? = nil,
        stationName: String? = nil,
        stationType: String? = nil
    ) {
        if isFavorite(stationId) {
            savedStations.removeAll { $0.id == stationId }
        } else {
            let sanitizedName = stationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (sanitizedName?.isEmpty == false) ? (sanitizedName ?? "") : "Station \(stationId)"
            savedStations.append(
                FavoriteStation(
                    id: stationId,
                    extId: extId,
                    globalId: globalId,
                    name: displayName,
                    type: stationType
                )
            )
        }
        save()
    }

    /// 判断站点是否已收藏。
    func isFavorite(_ stationId: String) -> Bool {
        savedStations.contains { $0.id == stationId }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(savedStations) {
            storage.set(data, forKey: key)
        }
    }

    private func loadFavorites() {
        // 新版数据：JSON 编码的 FavoriteStation 数组。
        if let data = storage.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FavoriteStation].self, from: data) {
            savedStations = decoded
            return
        }

        // 旧版数据迁移：仅保存了 [String] 站点 ID。
        if let legacyIDs = storage.array(forKey: key) as? [String] {
            savedStations = legacyIDs.map {
                FavoriteStation(id: $0, extId: nil, globalId: nil, name: "Station \($0)", type: nil)
            }
            save()
        }
    }
}
