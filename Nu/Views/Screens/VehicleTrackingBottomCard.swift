import SwiftUI
import MapKit

struct VehicleTrackingBottomCard: View {
    let vehicle: JourneyVehicle
    let motionLabel: String
    let motionColor: Color
    let lastUpdateDate: Date?
    let statusText: String
    let routeStopsAvailable: Bool
    let isShowingAlternateVehicle: Bool
    let onResetToPrimary: () -> Void
    let onOpenStops: () -> Void
    @Binding var cardState: VehicleCardState

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    cardState = cardState == .compact ? .expanded : .compact
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if cardState == .expanded {
                VStack(alignment: .leading, spacing: 12) {
                    topActions
                    detailCard
                }
                .padding(.top, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, VehicleTrackingUI.horizontalPadding)
        .padding(.bottom, cardState == .expanded ? 16 : 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: VehicleTrackingUI.bottomCardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: VehicleTrackingUI.bottomCardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: VehicleTrackingUI.bottomCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 30, y: 18)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(vehicle.line ?? L10n.tr("tracking.vehicle.fallback"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    if isShowingAlternateVehicle {
                        Text(L10n.tr("tracking.sheet.selectedVehicle"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(vehicle.direction ?? L10n.tr("tracking.vehicle.noDirection"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let nextStopName = vehicle.nextStopName, !nextStopName.isEmpty {
                    Label(L10n.tr("tracking.sheet.nextStop", nextStopName), systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                VehicleTrackingStatusPill(text: motionLabel, color: motionColor)
                LastUpdatedPill(lastUpdateDate: lastUpdateDate)
            }
        }
        .padding(.horizontal, 2)
    }

    private var topActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VehicleTrackingFloatingMessage(text: statusText)
                Spacer(minLength: 0)
                if isShowingAlternateVehicle {
                    Button(action: onResetToPrimary) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .indigo)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                LastUpdatedPill(lastUpdateDate: lastUpdateDate)
                VehicleTrackingStatusPill(text: motionLabel, color: motionColor)
                Spacer()
                if routeStopsAvailable {
                    Button(action: onOpenStops) {
                        Label(L10n.tr("tracking.sheet.open"), systemImage: "list.bullet.rectangle.portrait")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let stopName = vehicle.stopName, !stopName.isEmpty {
                highlightedRow(
                    title: L10n.tr("tracking.vehicle.currentStop", stopName),
                    subtitle: vehicle.nextStopName.map { L10n.tr("tracking.vehicle.nextStop", $0) }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                if let nextStopName = vehicle.nextStopName, !nextStopName.isEmpty {
                    VehicleTrackingInfoRow(icon: "arrow.triangle.branch", text: L10n.tr("tracking.vehicle.nextStop", nextStopName))
                }
                if let stopName = vehicle.stopName, !stopName.isEmpty {
                    VehicleTrackingInfoRow(icon: "mappin.circle", text: L10n.tr("tracking.vehicle.currentStop", stopName))
                }
                let lat = String(format: "%.5f", vehicle.coordinate.latitude)
                let lon = String(format: "%.5f", vehicle.coordinate.longitude)
                VehicleTrackingInfoRow(icon: "location", text: L10n.tr("tracking.vehicle.coordinates", lat, lon), monospaced: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: VehicleTrackingUI.innerCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VehicleTrackingUI.innerCardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 10)
    }

    private func highlightedRow(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.16), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
