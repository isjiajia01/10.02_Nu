import SwiftUI

struct VehicleTrackingStatusPill: View {
    let text: String
    var color: Color = .indigo

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.9))
            .clipShape(Capsule())
    }
}

enum VehicleTrackingUI {
    static let horizontalPadding: CGFloat = 16
    static let topOverlayPadding: CGFloat = 14
    static let bottomCardCornerRadius: CGFloat = 30
    static let innerCardCornerRadius: CGFloat = 22
    static let badgeCornerRadius: CGFloat = 999
}

struct VehicleTrackingFloatingMessage: View {
    let text: String
    var color: Color = .indigo

    var body: some View {
        VehicleTrackingStatusPill(text: text, color: color)
            .shadow(color: color.opacity(0.18), radius: 14, y: 8)
    }
}

struct VehicleTrackingInfoRow: View {
    let icon: String
    let text: String
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.indigo)
                .frame(width: 16)
            Text(text)
                .font(monospaced ? .footnote.monospacedDigit() : .footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

enum VehicleCardState {
    case compact
    case expanded
}

struct LastUpdatedPill: View {
    let lastUpdateDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(labelText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.teal.opacity(0.9))
                .clipShape(Capsule())
        }
    }

    private var labelText: String {
        guard let lastUpdateDate else { return "Updated —" }
        let age = Int(max(0, Date().timeIntervalSince(lastUpdateDate)))
        return "Updated \(age)s ago"
    }
}
