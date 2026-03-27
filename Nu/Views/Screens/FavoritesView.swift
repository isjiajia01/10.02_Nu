import SwiftUI
import UIKit

/// 收藏页面。
///
/// 说明：
/// - 展示用户已收藏的站点（站名 + ID）。
/// - 点击可直接进入对应站点发车板。
@MainActor
struct FavoritesView: View {
    private let dependencies: AppDependencies

    @StateObject private var favoritesManager: FavoritesManager

    init(dependencies: AppDependencies? = nil) {
        let resolvedDependencies = dependencies ?? AppDependencies.live
        self.dependencies = resolvedDependencies
        _favoritesManager = StateObject(wrappedValue: resolvedDependencies.favoritesManager)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(uiColor: .systemGroupedBackground), Color.indigo.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if favoritesManager.savedStations.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("favorites.empty.title"),
                        systemImage: "heart.slash",
                        description: Text(L10n.tr("favorites.empty.description"))
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Color.clear.frame(height: 10)
                            FavoritesSummaryCard(count: favoritesManager.savedStations.count)

                            ForEach(favoritesManager.savedStations) { station in
                                FavoriteSwipeRow(
                                    station: station,
                                    dependencies: dependencies
                                ) {
                                    remove(station)
                                }
                            }

                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle(L10n.tr("favorites.title"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func remove(_ station: FavoriteStation) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        favoritesManager.toggleFavorite(
            stationId: station.id,
            extId: station.extId,
            globalId: station.globalId,
            stationName: station.name,
            stationType: station.type
        )
    }
}

private struct FavoritesSummaryCard: View {
    private let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
            Text(L10n.tr("favorites.summary.savedCount", count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("favorites.summary.accessibility.label"))
        .accessibilityValue(L10n.tr("favorites.summary.accessibility.value", count))
    }

    init(count: Int) {
        self.count = count
    }
}

private struct FavoriteSwipeRow: View {
    private let station: FavoriteStation
    private let dependencies: AppDependencies
    private let onDelete: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false

    private let maxReveal: CGFloat = 84

    var body: some View {
        let revealProgress = min(max(abs(offsetX) / maxReveal, 0), 1)
        let actionColor = station.themeColor

        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .overlay(alignment: .trailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(actionColor.opacity(0.18))

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                offsetX = 0
                                isRevealed = false
                            }
                            onDelete()
                        } label: {
                            ZStack {
                                Label(
                                    L10n.tr("favorites.remove.accessibility", station.typeLabel),
                                    systemImage: "minus.circle.fill"
                                )
                                .labelStyle(.iconOnly)
                                .font(.system(size: 16, weight: .bold))

                                VStack(spacing: 4) {
                                    Image(systemName: station.iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .accessibilityHidden(true)
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .accessibilityHidden(true)
                                }
                            }
                            .foregroundStyle(actionColor)
                            .frame(width: maxReveal, height: 58)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: maxReveal)
                    .padding(.trailing, 4)
                    .opacity(max(revealProgress, isRevealed ? 1 : 0))
                }

            NavigationLink(
                destination: DepartureBoardView(
                    stationId: station.id,
                    stationExtId: station.extId,
                    stationGlobalId: station.globalId,
                    stationName: station.name,
                    stationType: station.type,
                    dependencies: dependencies
                )
            ) {
                GlassFavoriteStationCard(station: station)
            }
            .buttonStyle(.plain)
            .offset(x: offsetX)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let base = isRevealed ? -maxReveal : 0
                        let next = base + value.translation.width
                        offsetX = min(0, max(-maxReveal, next))
                    }
                    .onEnded { value in
                        let base = isRevealed ? -maxReveal : 0
                        let final = base + value.translation.width

                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            if final < -maxReveal * 0.45 {
                                offsetX = -maxReveal
                                isRevealed = true
                            } else {
                                offsetX = 0
                                isRevealed = false
                            }
                        }
                    }
            )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isRevealed)
    }

    init(
        station: FavoriteStation,
        dependencies: AppDependencies,
        onDelete: @escaping () -> Void
    ) {
        self.station = station
        self.dependencies = dependencies
        self.onDelete = onDelete
    }
}

#Preview {
    FavoritesView(dependencies: .preview)
}
