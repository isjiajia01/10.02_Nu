import SwiftUI

/// 可复用的站点类型图标容器。
///
/// 说明：
/// - 列表、收藏、地图都复用本组件，避免重复写样式。
/// - 默认是圆形渐变底 + 白色图标，可按场景调整尺寸。
struct StationTypeIconView: View {
    private let iconName: String
    private let gradient: LinearGradient
    private let shadowColor: Color
    private let size: CGFloat
    private let iconSize: CGFloat

    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: size, height: size)
            .shadow(color: shadowColor.opacity(0.35), radius: 6, x: 0, y: 3)
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    init(
        iconName: String,
        gradient: LinearGradient,
        shadowColor: Color,
        size: CGFloat,
        iconSize: CGFloat = 20
    ) {
        self.iconName = iconName
        self.gradient = gradient
        self.shadowColor = shadowColor
        self.size = size
        self.iconSize = iconSize
    }
}
