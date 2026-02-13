import SwiftUI

/// Apple 原生现代风发车卡片（类似 Apple Maps / Wallet 的干净材质感）。
struct GlassDepartureCard: View {
    private let departure: Departure
    private let catchProbabilityText: String?
    @ScaledMetric(relativeTo: .title3) private var lineBadgeSize: CGFloat = 54
    @ScaledMetric(relativeTo: .title2) private var lineCodeFontSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // 1. 左侧：线路号（交通路牌风格）。
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(getLineColor(type: departure.type, name: departure.name))
                    .frame(width: lineBadgeSize, height: lineBadgeSize)
                    .shadow(
                        color: getLineColor(type: departure.type, name: departure.name).opacity(0.3),
                        radius: 5,
                        x: 0,
                        y: 3
                    )

                VStack(spacing: 0) {
                    Text(typeBadge)
                        .font(.caption2.weight(.bold))
                        .opacity(0.8)
                        .foregroundStyle(.white)
                    Text(lineCode)
                        .font(.system(size: lineCodeFontSize, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)

            // 2. 中间：方向与状态。
            VStack(alignment: .leading, spacing: 4) {
                Text(departure.direction)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if departure.isDelayed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(L10n.tr("departures.delay.minutes", departure.delayMinutes))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    } else if departure.hasRealtimeData {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text(L10n.tr("departures.status.onTime"))
                            .font(.caption.weight(.medium))
                    } else {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                        Text(L10n.tr("departures.status.scheduled"))
                            .font(.caption.weight(.medium))
                    }
                }
                .foregroundStyle(statusColor)

                if let platformText = platformDisplayText {
                    Text(platformText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let changeText = trackChangeText {
                    Text(changeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // 3. 右侧：区间倒计时 + 可靠性信号。
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reliabilityColor)
                        .accessibilityHidden(true)

                    Text(intervalMainText)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(reliabilityColor)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                if showsMinuteUnit {
                    Text(L10n.tr("common.min"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let status = departure.catchStatus {
                    HStack(spacing: 6) {
                        DecisionPill(status: status)
                        if let catchProbabilityText {
                            Text(catchProbabilityText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(departure.accessibilitySummary)
        .accessibilityValue(accessibilityReliabilityText)
        .accessibilityHint(L10n.tr("departures.card.accessibility.hint", intervalMainText))
    }

    init(departure: Departure, catchProbabilityText: String? = nil) {
        self.departure = departure
        self.catchProbabilityText = catchProbabilityText
    }

    /// 右侧主文案：显示 "4-7" 这种区间格式。
    private var intervalMainText: String {
        guard let interval = minuteIntervalRaw else { return "--" }

        // 整个区间都在过去：车辆已走。
        if interval.upper < 0 {
            return L10n.tr("departures.interval.departed")
        }
        // 只要区间触及当前时刻，统一显示“Nu”，避免出现负数或“Nu-2”。
        if interval.lower <= 0 {
            return L10n.tr("departures.interval.now")
        }

        let lower = Int(floor(interval.lower))
        let upper = Int(ceil(interval.upper))

        if lower == upper {
            return "\(lower)"
        }
        return "\(lower)-\(upper)"
    }

    private var showsMinuteUnit: Bool {
        intervalMainText != L10n.tr("departures.interval.now")
            && intervalMainText != L10n.tr("departures.interval.departed")
            && intervalMainText != "--"
    }

    /// 使用 baseETA + uncertaintyRange 计算区间（单位：分钟，允许负值用于判断“已发车”）。
    private var minuteIntervalRaw: (lower: Double, upper: Double)? {
        guard let baseMinutes = departure.minutesUntilDepartureRaw else { return nil }

        let lowerValue = Double(baseMinutes) + departure.uncertaintyRange.lowerBound
        let upperValue = Double(baseMinutes) + departure.uncertaintyRange.upperBound

        return (min(lowerValue, upperValue), max(lowerValue, upperValue))
    }

    /// 可靠性颜色分段：
    /// - > 0.8: 绿色
    /// - 0.5...0.8: 橙色
    /// - < 0.5: 灰色
    private var reliabilityColor: Color {
        ReliabilitySignal(score: departure.reliabilityScore).color
    }

    private var accessibilityReliabilityText: String {
        ReliabilitySignal(score: departure.reliabilityScore).accessibilityText
    }

    private var statusColor: Color {
        if departure.isDelayed { return .orange }
        if departure.hasRealtimeData { return .green }
        return .secondary
    }

    private var platformDisplayText: String? {
        if let rtTrack = departure.rtTrack, !rtTrack.isEmpty {
            return L10n.tr("departures.track", rtTrack)
        }
        if let track = departure.track, !track.isEmpty {
            return L10n.tr("departures.track", track)
        }
        return nil
    }

    private var trackChangeText: String? {
        guard
            let track = departure.track, !track.isEmpty,
            let rtTrack = departure.rtTrack, !rtTrack.isEmpty,
            track != rtTrack
        else {
            return nil
        }
        return L10n.tr("departures.track.changed", track, rtTrack)
    }

    /// 类型角标。
    private var typeBadge: String {
        switch departure.type {
        case "BUS":
            return "BUS"
        case "METRO":
            return "M"
        case "TRAM":
            return "TRAM"
        case "FERRY":
            return "F"
        default:
            return "TOG"
        }
    }

    /// 线路显示：清理名称前缀（Bus/Metro/Tog）。
    private var lineCode: String {
        departure.name
            .replacingOccurrences(of: "Bus ", with: "")
            .replacingOccurrences(of: "Metro ", with: "")
            .replacingOccurrences(of: "Tog ", with: "")
    }

    /// 根据车辆类型与线路返回颜色。
    private func getLineColor(type: String, name: String) -> Color {
        if name.contains("5C") { return Color(hex: "00AEEF") }
        if type == "METRO" { return Color(hex: "00509E") }
        if type == "TRAM" { return Color(hex: "2E8B57") }
        if type == "FERRY" { return Color(hex: "00838F") }
        if type == "TOG" { return Color(hex: "B41629") }
        if name.contains("A") { return Color(hex: "B41629") }
        return Color(hex: "F4C443")
    }
}

private struct DecisionPill: View {
    private let status: CatchStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
            Text(status.message)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(minHeight: 24)
    }

    init(status: CatchStatus) {
        self.status = status
    }

    private var iconName: String {
        switch status {
        case .safe:
            return "figure.walk"
        case .risky:
            return "figure.run"
        case .impossible:
            return "clock.badge.exclamationmark"
        }
    }

    private var color: Color {
        switch status {
        case .safe:
            return .green
        case .risky:
            return .orange
        case .impossible:
            return .red
        }
    }
}

/// Hex 颜色扩展。
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64

        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.systemGray6)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        GlassDepartureCard(
            departure: Departure(
                name: "Bus 5C",
                type: "BUS",
                stop: "Kobenhavn H",
                time: "12:00",
                date: "11.02.26",
                rtTime: "12:03",
                rtDate: "11.02.26",
                direction: "Lufthavnen",
                finalStop: "Lufthavnen",
                track: "A",
                messages: nil
            )
        )
        .padding()
    }
}
