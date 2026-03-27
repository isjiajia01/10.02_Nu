import SwiftUI

/// 收藏站点玻璃卡片。
///
/// 说明：
/// - 复用统一站点类型图标，和地图/附近页保持一致。
/// - 右侧保留导向箭头，强调“点击进入发车板”。
struct GlassFavoriteStationCard: View {
    private let station: FavoriteStation
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 48

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            StationTypeIconView(
                iconName: displayIconName,
                gradient: station.themeGradient,
                shadowColor: station.themeColor,
                size: iconSize,
                iconSize: max(16, iconSize * 0.4)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text(station.typeLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(station.themeColor.opacity(0.12))
                        .foregroundStyle(station.themeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray.opacity(0.55))
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
        .accessibilityLabel(L10n.tr("favorites.card.accessibility.label", station.name, station.typeLabel))
        .accessibilityValue(L10n.tr("favorites.card.accessibility.value", station.id))
        .accessibilityHint(L10n.tr("favorites.card.accessibility.hint"))
    }

    init(station: FavoriteStation) {
        self.station = station
    }

    /// 收藏站点若无明确类型，使用更直观的交通站点图标，避免默认定位针过于抽象。
    private var displayIconName: String {
        station.typeLabel == "STATION" ? "mappin.circle.fill" : station.iconName
    }
}

#Preview {
    GlassFavoriteStationCard(
        station: FavoriteStation(id: "001", extId: nil, globalId: nil, name: "København H", type: "TOG")
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
