import SwiftUI

struct GlassStationCard: View {
    private let group: StationGroupModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            modeBadge
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.baseName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(group.mergedHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.baseName)
        .accessibilityValue(group.subtitle)
        .accessibilityHint(group.mergedHint)
    }

    init(group: StationGroupModel) {
        self.group = group
    }

    private var modeBadge: some View {
        let style = StationModeVisualStyle(mode: group.mergedMode)
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(style.badgeBackground)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: style.symbolName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(style.iconColor)
            }
    }
}
