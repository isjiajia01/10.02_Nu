import SwiftUI
import UIKit

struct StationModeVisualStyle {
    let symbolName: String
    let badgeBackground: Color
    let iconColor: Color
    let markerTint: UIColor
    let glyphTint: UIColor

    init(mode: StationModel.StationMode) {
        switch mode {
        case .bus:
            symbolName = "bus.fill"
            badgeBackground = Color.orange.opacity(0.22)
            iconColor = Color.orange.opacity(0.95)
            markerTint = UIColor.systemOrange.withAlphaComponent(0.35)
            glyphTint = UIColor.systemOrange
        case .metro:
            symbolName = "tram.fill"
            badgeBackground = Color.blue.opacity(0.20)
            iconColor = Color.blue.opacity(0.95)
            markerTint = UIColor.systemBlue.withAlphaComponent(0.30)
            glyphTint = UIColor.systemBlue
        case .tog:
            symbolName = "train.side.front.car"
            badgeBackground = Color.red.opacity(0.18)
            iconColor = Color.red.opacity(0.92)
            markerTint = UIColor.systemRed.withAlphaComponent(0.28)
            glyphTint = UIColor.systemRed
        case .mixed:
            symbolName = "arrow.triangle.branch"
            badgeBackground = Color.purple.opacity(0.20)
            iconColor = Color.purple.opacity(0.92)
            markerTint = UIColor.systemPurple.withAlphaComponent(0.30)
            glyphTint = UIColor.systemPurple
        case .unknown:
            symbolName = "questionmark.circle"
            badgeBackground = Color(uiColor: .systemGray5)
            iconColor = Color(uiColor: .systemGray)
            markerTint = UIColor.systemGray4
            glyphTint = UIColor.systemGray
        }
    }
}
