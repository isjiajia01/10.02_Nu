import Foundation

enum CatchStatus: String, Codable, Hashable {
    case safe
    case risky
    case impossible

    var message: String {
        switch self {
        case .safe:
            return L10n.tr("catch.safe")
        case .risky:
            return L10n.tr("catch.risky")
        case .impossible:
            return L10n.tr("catch.impossible")
        }
    }
}

/// 运筹学逻辑服务（纯计算层，无 UI 依赖）。
///
/// 当前阶段：
/// - 实现“启发式误差分布”：
///   1) 有实时数据：误差 ~ N(0, 2min)
///   2) 仅时刻表：误差 ~ U(0, 5min)
///
/// 后续可继续扩展：
/// - P(catch) 概率计算
/// - 可靠性分数更新
/// - 帕累托前沿排序
struct ORService {
    struct HeuristicDistributionResult: Hashable {
        let uncertaintyRange: UncertaintyRange
        let reliabilityScore: Double
    }

    /// 按教授蓝图计算启发式不确定性区间与初始可靠性分数。
    ///
    /// - Returns:
    ///   - `uncertaintyRange`: 建议显示的 ETA 误差区间（分钟）
    ///   - `reliabilityScore`: 0...1，数值越大表示越可靠
    func heuristicDistribution(for departure: Departure) -> HeuristicDistributionResult {
        let hasRealtime = departure.rtTime != nil

        if hasRealtime {
            // N(0, 2) 的 P05/P95 近似值：±1.64485*2 = ±3.29
            return HeuristicDistributionResult(
                uncertaintyRange: UncertaintyRange(lowerBound: -3.29, upperBound: 3.29),
                reliabilityScore: 0.82
            )
        } else {
            // U(0, 5) 的 P05/P95：0.25 与 4.75
            return HeuristicDistributionResult(
                uncertaintyRange: UncertaintyRange(lowerBound: 0.25, upperBound: 4.75),
                reliabilityScore: 0.55
            )
        }
    }

    /// 用于把计算结果写回模型（不改动原对象，返回新对象）。
    func enrich(_ departure: Departure) -> Departure {
        let result = heuristicDistribution(for: departure)
        return Departure(
            journeyRef: departure.journeyRef,
            name: departure.name,
            type: departure.type,
            stop: departure.stop,
            time: departure.time,
            date: departure.date,
            rtTime: departure.rtTime,
            rtDate: departure.rtDate,
            direction: departure.direction,
            finalStop: departure.finalStop,
            track: departure.track,
            rtTrack: departure.rtTrack,
            messages: departure.messages,
            passListStops: departure.passListStops,
            uncertaintyRange: result.uncertaintyRange,
            reliabilityScore: result.reliabilityScore,
            catchProbability: departure.catchProbability,
            catchStatus: departure.catchStatus
        )
    }

    /// 计算“能否赶上车”的决策状态。
    ///
    /// 判定逻辑（分钟域）：
    /// - 用户到站时刻 = `walkingMinutes`
    /// - 车辆到站窗口 = `baseETA + uncertaintyRange`
    /// - 若用户早于窗口下界：safe
    /// - 若用户晚于窗口上界：impossible
    /// - 落在窗口内：risky
    func calculateCatchProbability(departure: Departure, walkingMinutes: Double) -> CatchStatus {
        guard let baseMinutes = departure.minutesUntilDepartureRaw else { return .risky }

        let lower = Double(baseMinutes) + min(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound)
        let upper = Double(baseMinutes) + max(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound)

        if walkingMinutes <= lower { return .safe }
        if walkingMinutes > upper { return .impossible }
        return .risky
    }

    /// 把“赶车决策”结果写回模型。
    func enrichDecision(departure: Departure, walkingMinutes: Double) -> Departure {
        let status = calculateCatchProbability(departure: departure, walkingMinutes: walkingMinutes)
        let probability = estimatedCatchProbability(
            departure: departure,
            walkingMinutes: walkingMinutes,
            status: status
        )

        return Departure(
            journeyRef: departure.journeyRef,
            name: departure.name,
            type: departure.type,
            stop: departure.stop,
            time: departure.time,
            date: departure.date,
            rtTime: departure.rtTime,
            rtDate: departure.rtDate,
            direction: departure.direction,
            finalStop: departure.finalStop,
            track: departure.track,
            rtTrack: departure.rtTrack,
            messages: departure.messages,
            passListStops: departure.passListStops,
            uncertaintyRange: departure.uncertaintyRange,
            reliabilityScore: departure.reliabilityScore,
            catchProbability: probability,
            catchStatus: status
        )
    }

    private func estimatedCatchProbability(
        departure: Departure,
        walkingMinutes: Double,
        status: CatchStatus
    ) -> Double {
        guard let baseMinutes = departure.minutesUntilDepartureRaw else { return 0.5 }
        let lower = Double(baseMinutes) + min(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound)
        let upper = Double(baseMinutes) + max(departure.uncertaintyRange.lowerBound, departure.uncertaintyRange.upperBound)
        let width = max(upper - lower, 0.1)

        switch status {
        case .safe:
            return 0.97
        case .impossible:
            return 0.03
        case .risky:
            let ratio = (upper - walkingMinutes) / width
            return min(max(ratio, 0.05), 0.95)
        }
    }
}
