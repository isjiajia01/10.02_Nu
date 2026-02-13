import SwiftUI

/// 发车可靠性分级规则（供卡片与图例统一复用）。
enum ReliabilitySignal {
    case high
    case medium
    case low

    init(score: Double) {
        if score > 0.8 {
            self = .high
        } else if score >= 0.5 {
            self = .medium
        } else {
            self = .low
        }
    }

    var color: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            // 低可靠在深色玻璃背景里需要更高对比度，避免灰色“看不见”。
            return Color(
                uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.white.withAlphaComponent(0.65)
                        : UIColor.systemGray
                }
            )
        }
    }

    var title: String {
        switch self {
        case .high:
            return L10n.tr("reliability.high")
        case .medium:
            return L10n.tr("reliability.medium")
        case .low:
            return L10n.tr("reliability.low")
        }
    }

    var accessibilityText: String {
        switch self {
        case .high:
            return L10n.tr("reliability.a11y.high")
        case .medium:
            return L10n.tr("reliability.a11y.medium")
        case .low:
            return L10n.tr("reliability.a11y.low")
        }
    }
}
