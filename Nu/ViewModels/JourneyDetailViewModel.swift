import Foundation
import SwiftUI
import Combine

struct VehiclePositionInference: Equatable {
    enum Mode: Equatable {
        case between
        case atStop
        case unknown
    }

    let fromRealtime: Bool
    let fromStopIdx: Int?
    let toStopIdx: Int?
    let fromStopName: String?
    let toStopName: String?
    let mode: Mode

    static let unknown = VehiclePositionInference(
        fromRealtime: false,
        fromStopIdx: nil,
        toStopIdx: nil,
        fromStopName: nil,
        toStopName: nil,
        mode: .unknown
    )

    var estimatedBadgeText: String {
        fromRealtime ? L10n.tr("journeyDetail.estimated.rt") : L10n.tr("journeyDetail.estimated.sched")
    }

    var accessibilityLabel: String? {
        guard mode == .between, let fromStopName, let toStopName else { return nil }
        let source = fromRealtime
            ? L10n.tr("journeyDetail.estimated.source.realtime")
            : L10n.tr("journeyDetail.estimated.source.scheduled")
        return L10n.tr("journeyDetail.estimated.segment.a11y", fromStopName, toStopName, source)
    }
}

@MainActor
final class JourneyDetailViewModel: ObservableObject {
    let forceEagerRenderingForDebug = ProcessInfo.processInfo.environment["NU_JDETAIL_FORCE_EAGER"] == "1"

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rows: [StopRowModel] = []
    @Published var passedRows: [StopRowModel] = []
    @Published var upcomingRows: [StopRowModel] = []
    @Published var totalTravelSummaryText: String = L10n.tr("journeyDetail.destination.pending")
    @Published var currentIndex: Int?
    @Published var nextIndex: Int?
    @Published var currentOrNextIndex: Int?
    @Published var vehiclePositionInference: VehiclePositionInference = .unknown

    func load(
        journeyID: String,
        operationDate: String?,
        fallbackStops: [JourneyStop],
        currentStopName: String,
        apiService: APIServiceProtocol
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            let detail = try await apiService.fetchJourneyDetail(id: journeyID, date: operationDate)
            let baseStops = resolveBaseStops(
                journeyID: journeyID,
                operationDate: operationDate,
                fallbackStops: fallbackStops,
                currentStopName: currentStopName,
                detailStops: detail.stops
            )
            applyDerived(
                journeyID: journeyID,
                stops: baseStops,
                operationDate: operationDate,
                currentStopName: currentStopName
            )
        } catch {
            if !fallbackStops.isEmpty {
                applyDerived(
                    journeyID: journeyID,
                    stops: fallbackStops,
                    operationDate: operationDate,
                    currentStopName: currentStopName
                )
            } else {
                let minimal = JourneyFallbackStopsBuilder.build(from: journeyID, currentStopName: currentStopName)
                if !minimal.isEmpty {
                    applyDerived(
                        journeyID: journeyID,
                        stops: minimal,
                        operationDate: operationDate,
                        currentStopName: currentStopName
                    )
                } else {
                    errorMessage = AppErrorPresenter.message(for: error, context: .journeyDetail)
                }
            }
        }

        isLoading = false
    }

    private func resolveBaseStops(
        journeyID: String,
        operationDate: String?,
        fallbackStops: [JourneyStop],
        currentStopName: String,
        detailStops: [JourneyStop]
    ) -> [JourneyStop] {
        if !detailStops.isEmpty {
            return detailStops
        }
        if !fallbackStops.isEmpty {
            return fallbackStops
        }
        return JourneyFallbackStopsBuilder.build(from: journeyID, currentStopName: currentStopName)
    }

    private func applyDerived(
        journeyID: String,
        stops: [JourneyStop],
        operationDate: String?,
        currentStopName: String
    ) {
        #if DEBUG
        JourneyZoneParser.debugRawStopsDump(journeyID: journeyID, stops: stops)
        #endif

        rows = JourneyDisplayRowBuilder.buildRows(journeyID: journeyID, stops: stops)

        let displayable = rows.map(\.stop)
        let progress = JourneyProgressEstimator.infer(
            stops: displayable,
            fallbackCurrentStopName: currentStopName,
            operationDate: operationDate
        )

        currentIndex = progress.currentIndex
        nextIndex = progress.nextIndex
        currentOrNextIndex = progress.currentOrNextIndex
        totalTravelSummaryText = progress.minutesToDestination.map {
            L10n.tr("journeyDetail.destination.minutes", $0)
        } ?? L10n.tr("journeyDetail.destination.pending")
        vehiclePositionInference = Self.buildVehicleInference(progress: progress, stops: displayable)

        if let split = currentOrNextIndex, split > 0 {
            passedRows = Array(rows.prefix(split))
            upcomingRows = split < rows.count ? Array(rows.suffix(from: split)) : [rows.last].compactMap { $0 }
        } else {
            passedRows = []
            upcomingRows = rows
        }
    }

    static func normalizeTimeToMinute(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.contains(":"), clean.count >= 5 {
            return String(clean.prefix(5))
        }
        return clean
    }

    private static func buildVehicleInference(
        progress: JourneyProgressEstimation,
        stops: [JourneyStop]
    ) -> VehiclePositionInference {
        switch progress.status {
        case .between(let from, let to):
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: progress.currentIndex,
                toStopIdx: progress.nextIndex,
                fromStopName: from,
                toStopName: to,
                mode: .between
            )
        case .at(let name):
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: progress.currentIndex,
                toStopIdx: nil,
                fromStopName: name,
                toStopName: nil,
                mode: .atStop
            )
        case .nearDestination:
            let idx = max(stops.count - 1, 0)
            return VehiclePositionInference(
                fromRealtime: progress.usesRealtime,
                fromStopIdx: stops.isEmpty ? nil : idx,
                toStopIdx: nil,
                fromStopName: stops.last?.name,
                toStopName: nil,
                mode: .atStop
            )
        case .unknown:
            return .unknown
        }
    }
}
