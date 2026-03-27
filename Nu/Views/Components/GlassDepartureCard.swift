import SwiftUI

/// Apple-native departure card (clean material style like Apple Maps / Wallet).
///
/// Right side shows: single countdown number + CatchBucket pill + optional %.
/// No ETA interval range is displayed on the card.
struct GlassDepartureCard: View {
    private let departure: Departure
    private let catchProbabilityText: String?
    private let directionText: String?
    private let directionStyle: DepartureBoardViewModel.DirectionChipStyle
    @ScaledMetric(relativeTo: .title3) private var lineBadgeSize: CGFloat = 54
    @ScaledMetric(relativeTo: .title2) private var lineCodeFontSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // 1. Left: line badge.
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

            // 2. Center: direction chip + destination & status.
            VStack(alignment: .leading, spacing: 4) {
                if let directionText {
                    DirectionChip(text: directionText, style: directionStyle)
                }

                Text(departure.direction)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    if departure.isDelayed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(L10n.tr("departures.delay.minutes", departure.delayMinutes))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    } else if departure.hasRealtimeData {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
                        Text(L10n.tr("departures.status.onTime"))
                            .font(.caption.weight(.medium))
                    } else {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                            .accessibilityHidden(true)
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

            // 3. Right: single countdown + catch bucket pill + optional %.
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reliabilityColor)
                        .accessibilityHidden(true)

                    Text(countdownText)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(reliabilityColor)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                if showsMinuteUnit {
                    Text(L10n.tr("common.min"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let bucket = departure.catchBucket {
                    HStack(spacing: 6) {
                        CatchBucketPill(bucket: bucket)
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
        .accessibilityHint(L10n.tr("departures.card.accessibility.hint", countdownText))
    }

    init(
        departure: Departure,
        catchProbabilityText: String? = nil,
        directionText: String? = nil,
        directionStyle: DepartureBoardViewModel.DirectionChipStyle = .filled
    ) {
        self.departure = departure
        self.catchProbabilityText = catchProbabilityText
        self.directionText = directionText
        self.directionStyle = directionStyle
    }

    /// Single countdown number (no interval range).
    private var countdownText: String {
        guard let minutes = departure.minutesUntilDepartureRaw else { return "--" }
        if minutes < 0 {
            return L10n.tr("departures.interval.departed")
        }
        if minutes == 0 {
            return L10n.tr("departures.interval.now")
        }
        return "\(minutes)"
    }

    private var showsMinuteUnit: Bool {
        countdownText != L10n.tr("departures.interval.now")
            && countdownText != L10n.tr("departures.interval.departed")
            && countdownText != "--"
    }

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

    private var typeBadge: String {
        switch departure.type {
        case "BUS":   return "BUS"
        case "METRO": return "M"
        case "TRAM":  return "TRAM"
        case "FERRY": return "F"
        default:      return "TOG"
        }
    }

    private var lineCode: String {
        departure.name
            .replacingOccurrences(of: "Bus ", with: "")
            .replacingOccurrences(of: "Metro ", with: "")
            .replacingOccurrences(of: "Tog ", with: "")
    }

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

// MARK: - CatchBucketPill

private struct CatchBucketPill: View {
    private let bucket: CatchBucket

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
            Text(bucket.label)
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

    init(bucket: CatchBucket) {
        self.bucket = bucket
    }

    private var iconName: String {
        switch bucket {
        case .likely:   return "figure.walk"
        case .tight:    return "figure.run"
        case .unlikely: return "clock.badge.exclamationmark"
        }
    }

    private var color: Color {
        switch bucket {
        case .likely:   return .green
        case .tight:    return .orange
        case .unlikely: return .red
        }
    }
}

// MARK: - DirectionChip

private struct DirectionChip: View {
    let text: String
    let style: DepartureBoardViewModel.DirectionChipStyle

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(style == .filled ? .white : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style == .filled ? Color.secondary.opacity(0.6) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(style == .stroked ? Color.secondary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Color hex extension

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
            ),
            directionText: "→ Lufthavnen",
            directionStyle: .filled
        )
        .padding()
    }
}
