import SwiftUI

@MainActor
struct StationHubView: View {
    private let group: StationGroupModel
    private let dependencies: AppDependencies

    @State private var selectedEntranceId: String?
    @State private var preferredMode: PreferredMode = .all

    init(
        group: StationGroupModel,
        dependencies: AppDependencies? = nil
    ) {
        let resolvedDependencies = dependencies ?? AppDependencies.live
        self.group = group
        self.dependencies = resolvedDependencies
        _selectedEntranceId = State(initialValue: group.bestEntrance().id)
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.tr("stations.hub.modePicker"), selection: $preferredMode) {
                    ForEach(availableModes) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                NavigationLink(
                    destination: makeDepartureBoardDestination(for: bestEntrance)
                ) {
                    HStack(spacing: 10) {
                        entranceModeBadge(bestEntrance)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("stations.hub.bestEntrance"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(bestEntrance.name)
                                .font(.headline)

                            Text(bestEntrance.stationModeSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(L10n.tr("stations.hub.entrances")) {
                ForEach(sortedEntrances, id: \.id) { station in
                    NavigationLink(
                        destination: makeDepartureBoardDestination(for: station)
                    ) {
                        HStack(spacing: 8) {
                            entranceModeBadge(station)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.entranceLabel)
                                    .font(.subheadline.weight(.semibold))

                                Text(station.stationModeSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if station.id == bestEntrance.id {
                                Text(L10n.tr("stations.hub.recommended"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.baseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bestEntrance: StationModel {
        group.bestEntrance(preferredMode: selectedEntranceMode)
    }

    private var selectedEntranceMode: StationModel.StationMode? {
        if let explicit = preferredMode.stationMode {
            return explicit
        }
        guard let selectedEntranceId else { return nil }
        return group.stations.first(where: { $0.id == selectedEntranceId })?.stationMode
    }

    private var sortedEntrances: [StationModel] {
        group.stations.sorted { lhs, rhs in
            let lhsModeMatch = modeMatchScore(lhs)
            let rhsModeMatch = modeMatchScore(rhs)
            if lhsModeMatch != rhsModeMatch { return lhsModeMatch < rhsModeMatch }

            let lhsDist = lhs.distanceMeters ?? .greatestFiniteMagnitude
            let rhsDist = rhs.distanceMeters ?? .greatestFiniteMagnitude
            if lhsDist != rhsDist { return lhsDist < rhsDist }

            return lhs.name < rhs.name
        }
    }

    private var availableModes: [PreferredMode] {
        var result: [PreferredMode] = [.all]
        let modes = Set(group.stations.map(\.stationMode))

        if modes.contains(.bus) { result.append(.bus) }
        if modes.contains(.metro) { result.append(.metro) }
        if modes.contains(.tog) { result.append(.tog) }
        if modes.contains(where: {
            if case .mixed = $0 { return true }
            return false
        }) {
            result.append(.mixed)
        }

        return result
    }

    private func modeMatchScore(_ station: StationModel) -> Int {
        switch preferredMode {
        case .all:
            return 1
        case .bus:
            return station.stationMode == .bus ? 0 : 1
        case .metro:
            return station.stationMode == .metro ? 0 : 1
        case .tog:
            return station.stationMode == .tog ? 0 : 1
        case .mixed:
            if case .mixed = station.stationMode { return 0 }
            return 1
        }
    }

    private func makeDepartureBoardDestination(for station: StationModel) -> some View {
        DepartureBoardView(
            stationId: station.id,
            stationExtId: station.extId,
            stationGlobalId: station.globalId,
            stationName: station.name,
            stationType: station.stationType,
            walkingDestinations: makeWalkingDestinations(),
            dependencies: dependencies
        )
    }

    private func makeWalkingDestinations() -> [WalkingETADestination] {
        group.stations.map { station in
            WalkingETADestination(
                stopId: station.id,
                name: station.name,
                groupId: group.id,
                latitude: station.latitude,
                longitude: station.longitude,
                mode: modeFor(station),
                isRecommended: station.id == bestEntrance.id
            )
        }
    }

    /// 每个入口行的彩色 mode 小图标，基于 entry 自身的 stationMode（不继承 group）。
    private func entranceModeBadge(_ station: StationModel) -> some View {
        let style = StationModeVisualStyle(mode: station.stationMode)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(style.badgeBackground)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: style.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style.iconColor)
            }
    }
}

private func modeFor(_ station: StationModel) -> WalkingETADestination.Mode {
    switch station.stationMode {
    case .bus:
        return .bus
    case .metro:
        return .metro
    case .tog:
        return .tog
    case .mixed(let set):
        if set.contains(.metro) { return .metro }
        if set.contains(.tog) { return .tog }
        if set.contains(.bus) { return .bus }
        return .unknown
    case .unknown:
        return .unknown
    }
}

private enum PreferredMode: Hashable, Identifiable {
    case all
    case bus
    case metro
    case tog
    case mixed

    var id: String {
        switch self {
        case .all: return "all"
        case .bus: return "bus"
        case .metro: return "metro"
        case .tog: return "tog"
        case .mixed: return "mixed"
        }
    }

    var label: String {
        switch self {
        case .all: return L10n.tr("stations.hub.mode.all")
        case .bus: return L10n.tr("mode.bus")
        case .metro: return L10n.tr("mode.metro")
        case .tog: return L10n.tr("mode.tog")
        case .mixed: return L10n.tr("stations.hub.mode.mixed")
        }
    }

    var stationMode: StationModel.StationMode? {
        switch self {
        case .all: return nil
        case .bus: return .bus
        case .metro: return .metro
        case .tog: return .tog
        case .mixed: return nil
        }
    }
}
