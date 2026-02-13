import SwiftUI

/// 轻量状态提示条（Toast）。
///
/// 说明：
/// - 用于“已有内容时的非阻断错误提示”。
/// - 避免网络瞬断时整页变成空白，提升稳定感与审核体验。
struct StatusToast: View {
    enum Tone {
        case error
        case info

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    private let tone: Tone
    private let message: String
    private let onDismiss: () -> Void

    init(
        tone: Tone = .error,
        message: String,
        onDismiss: @escaping () -> Void
    ) {
        self.tone = tone
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("toast.dismiss"))
            .accessibilityHint(L10n.tr("toast.dismiss.hint"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("toast.status"))
        .accessibilityValue(message)
    }
}
