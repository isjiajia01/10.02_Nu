import Foundation
import CoreLocation

struct StationGroupModel: Identifiable, Hashable {
    let id: String
    let baseName: String
    let stations: [StationModel]
    let mergedMode: StationModel.StationMode

    init(id: String, baseName: String, stations: [StationModel]) {
        self.id = id
        self.baseName = baseName
        self.stations = stations
        self.mergedMode = Self.resolveMergedMode(stations)
        Self.debugGroupMode(
            key: id,
            name: baseName,
            stations: stations,
            finalMode: mergedMode
        )
    }

    var nearestDistanceMeters: Double? {
        stations.compactMap(\.distanceMeters).min()
    }

    var entranceCount: Int {
        stations.count
    }

    private static func resolveMergedMode(_ stations: [StationModel]) -> StationModel.StationMode {
        let singles = stations.reduce(into: Set<StationModel.StationMode.SingleMode>()) { acc, station in
            switch station.stationMode {
            case .bus: acc.insert(.bus)
            case .metro: acc.insert(.metro)
            case .tog: acc.insert(.tog)
            case .mixed(let set): acc.formUnion(set)
            case .unknown: break
            }
        }
        if singles.count > 1 { return .mixed(singles) }
        if let single = singles.first {
            switch single {
            case .bus: return .bus
            case .metro: return .metro
            case .tog: return .tog
            }
        }
        return .unknown
    }

    private static func modeSetString(_ modes: Set<StationModel.StationMode.SingleMode>) -> String {
        modes.map { $0.rawValue.lowercased() }.sorted().joined(separator: ",")
    }

    private static func modeLabel(_ mode: StationModel.StationMode) -> String {
        switch mode {
        case .bus:
            return "bus"
        case .metro:
            return "metro"
        case .tog:
            return "tog"
        case .mixed(let set):
            return "mixed(\(modeSetString(set)))"
        case .unknown:
            return "unknown"
        }
    }

    private static func debugGroupMode(
        key: String,
        name: String,
        stations: [StationModel],
        finalMode: StationModel.StationMode
    ) {
        #if DEBUG
        emit("[ModeDebug][Group] key=\(key) name=\"\(name)\" members=\(stations.count)")

        var aggregated = Set<StationModel.StationMode.SingleMode>()
        for station in stations {
            let resolution = station.modeResolution
            aggregated.formUnion(resolution.modes)

            let productsToken = station.products?.isEmpty == false ? "[\(station.products!.joined(separator: ","))]" : "[]"
            let rawProductsParts = [
                "bitmask=\(station.productsBitmask.map(String.init) ?? "nil")",
                "tokens=\(productsToken)",
                "productAtStopCount=\(station.productAtStop?.count ?? 0)"
            ].joined(separator: " ")
            let coord = String(format: "(%.6f,%.6f)", station.latitude, station.longitude)
            let memberMode = resolution.modes.isEmpty ? "unknown" : modeSetString(resolution.modes)
            let zoneText = station.zone?.trimmingCharacters(in: .whitespacesAndNewlines)
            emit("  - stop id=\(station.id) name=\"\(station.name)\" type=\(station.type ?? "nil") products=\(productsToken) rawProducts={\(rawProductsParts)} zone=\(zoneText?.isEmpty == false ? zoneText! : "nil") zoneSource=\(station.zoneSource) coord=\(coord) mode=\(memberMode) reason=\(resolution.reason)")
        }

        let aggregatedText = aggregated.isEmpty ? "unknown" : modeSetString(aggregated)
        emit("  => aggregated={\(aggregatedText)} final=\(modeLabel(finalMode))")
        #endif
    }

    private static func emit(_ message: String) {
        fputs("\(message)\n", stderr)
    }

    var subtitle: String {
        var parts: [String] = [mergedMode.primaryLabel]
        if let nearestDistanceMeters {
            parts.append(L10n.tr("station.distance.metersShort", Int(nearestDistanceMeters)))
        }
        return parts.joined(separator: " · ")
    }

    var mergedHint: String {
        L10n.tr("stations.group.mergedHint", entranceCount)
    }

    func bestEntrance(preferredMode: StationModel.StationMode? = nil) -> StationModel {
        let modePreference = preferredMode ?? mergedMode
        return stations.sorted { lhs, rhs in
            let lhsDist = lhs.distanceMeters ?? .greatestFiniteMagnitude
            let rhsDist = rhs.distanceMeters ?? .greatestFiniteMagnitude
            if lhsDist != rhsDist { return lhsDist < rhsDist }

            let lhsMode = modePriority(station: lhs, preferredMode: modePreference)
            let rhsMode = modePriority(station: rhs, preferredMode: modePreference)
            if lhsMode != rhsMode { return lhsMode < rhsMode }

            let lhsRich = richnessScore(lhs)
            let rhsRich = richnessScore(rhs)
            if lhsRich != rhsRich { return lhsRich > rhsRich }

            return lhs.id < rhs.id
        }.first ?? stations[0]
    }

    private func modePriority(station: StationModel, preferredMode: StationModel.StationMode) -> Int {
        station.stationMode == preferredMode ? 0 : 1
    }

    private func richnessScore(_ station: StationModel) -> Int {
        var score = 0
        score += station.products?.count ?? 0
        if station.type != nil { score += 1 }
        if station.category != nil { score += 1 }
        return score
    }
}

enum StationGrouping {
    static func buildGroups(_ stations: [StationModel], thresholdMeters: Double = 250) -> [StationGroupModel] {
        let sorted = stations.sorted { ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude) }

        let withGroupId = sorted.filter { ($0.stationGroupId?.isEmpty == false) }
        let withoutGroupId = sorted.filter { ($0.stationGroupId?.isEmpty != false) }

        var groups: [StationGroupModel] = []

        let groupedByAPI = Dictionary(grouping: withGroupId) { $0.stationGroupId ?? $0.baseName }
        for (groupID, members) in groupedByAPI {
            let base = mostCommonBaseName(in: members)
            groups.append(StationGroupModel(id: "api:\(groupID)", baseName: base, stations: members))
        }

        let fallbackBuckets = Dictionary(grouping: withoutGroupId) { $0.baseName.lowercased() }
        for (_, members) in fallbackBuckets {
            let clusters = clusterByDistance(members, thresholdMeters: thresholdMeters)
            for (index, cluster) in clusters.enumerated() {
                let base = cluster.first?.baseName ?? L10n.tr("stations.group.unknown")
                let anchor = cluster.first
                let lat = anchor?.latitude ?? 0
                let lon = anchor?.longitude ?? 0
                let id = "fallback:\(base.lowercased()):\(index):\(Int(lat * 10_000)):\(Int(lon * 10_000))"
                groups.append(StationGroupModel(id: id, baseName: base, stations: cluster))
            }
        }

        return groups.sorted { ($0.nearestDistanceMeters ?? .greatestFiniteMagnitude) < ($1.nearestDistanceMeters ?? .greatestFiniteMagnitude) }
    }

    private static func mostCommonBaseName(in stations: [StationModel]) -> String {
        let counts = Dictionary(grouping: stations) { $0.baseName }.mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? stations.first?.baseName ?? L10n.tr("stations.group.unknown")
    }

    private static func clusterByDistance(_ members: [StationModel], thresholdMeters: Double) -> [[StationModel]] {
        var clusters: [[StationModel]] = []
        for station in members.sorted(by: { ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude) }) {
            if let idx = clusters.firstIndex(where: { cluster in
                cluster.contains { other in
                    let a = CLLocation(latitude: station.latitude, longitude: station.longitude)
                    let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
                    return a.distance(from: b) <= thresholdMeters
                }
            }) {
                clusters[idx].append(station)
            } else {
                clusters.append([station])
            }
        }
        return clusters
    }
}
