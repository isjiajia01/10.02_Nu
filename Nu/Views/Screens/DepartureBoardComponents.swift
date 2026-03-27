import SwiftUI

enum DepartureBoardUI {
    static let screenHorizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
}

struct DepartureBoardWalkAndDelayCard: View {
    let walkingTimeTitleText: String
    let walkingTimeDisplayText: String
    let walkingEstimateHintText: String?
    let sourceLabel: String
    let updateStatusText: String?
    let departureDelayMinutes: Int
    let departureDelayDisplayText: String
    let activePreset: DepartureBoardViewModel.WalkPreset?
    let isExpanded: Bool
    let onDelayChange: (Int) -> Void
    let onPresetAtStation: () -> Void
    let onPresetOnTheWay: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(walkingTimeTitleText, systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(walkingTimeDisplayText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            if let walkingEstimateHintText {
                Text(walkingEstimateHintText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(L10n.tr("departures.walking.delay.label"), systemImage: "clock.arrow.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(departureDelayDisplayText)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                Button(L10n.tr("departures.walking.preset.inStation"), action: onPresetAtStation)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(activePreset == .alreadyInStation ? .green : .secondary.opacity(0.35))

                Button(L10n.tr("departures.walking.preset.onTheWay"), action: onPresetOnTheWay)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(activePreset == .onTheWay ? .blue : .secondary.opacity(0.35))

                Text(sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let updateStatusText {
                    Text(updateStatusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer()

                Button(isExpanded ? L10n.tr("common.collapse") : L10n.tr("common.adjust")) {
                    onToggleExpand()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isExpanded {
                HStack(spacing: 8) {
                    ForEach([0, 5, 10], id: \.self) { preset in
                        Button(delayPresetLabel(preset)) {
                            onDelayChange(preset)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(departureDelayMinutes == preset ? .blue : .secondary.opacity(0.3))
                    }
                    Spacer()
                }

                Slider(
                    value: Binding(
                        get: { Double(departureDelayMinutes) },
                        set: { onDelayChange(Int($0.rounded())) }
                    ),
                    in: 0...20,
                    step: 1
                ) {
                    Text(L10n.tr("departures.walking.delay.slider"))
                } minimumValueLabel: {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("20")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityValue(L10n.tr("departures.walking.accessibility.value", departureDelayMinutes))
                .accessibilityHint(L10n.tr("departures.walking.accessibility.hint"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func delayPresetLabel(_ minutes: Int) -> String {
        if minutes == 0 {
            return L10n.tr("departures.walking.delay.preset.0")
        } else if minutes == 5 {
            return L10n.tr("departures.walking.delay.preset.5")
        } else {
            return L10n.tr("departures.walking.delay.preset.10")
        }
    }
}

struct DepartureBoardReliabilityLegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            legendItem(signal: .high, detail: "> 0.8")
            legendItem(signal: .medium, detail: "0.5-0.8")
            legendItem(signal: .low, detail: "< 0.5")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("departures.reliability.legend.label"))
        .accessibilityValue(L10n.tr("departures.reliability.legend.value"))
    }

    @ViewBuilder
    private func legendItem(signal: ReliabilitySignal, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(signal.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(signal.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 24)
    }
}
