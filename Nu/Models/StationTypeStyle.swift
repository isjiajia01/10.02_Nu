import SwiftUI

/// 统一站点类型视觉协议。
///
/// 说明：
/// - 只要提供 `stationType`，即可复用同一套图标、颜色、渐变和标签文案。
/// - 用于列表卡片、地图标记、收藏页，确保视觉一致性。
protocol StationTypeStylable {
    var stationType: String? { get }
}

extension StationTypeStylable {
    var iconName: String {
        switch normalizedType {
        case "BUS": return "bus.fill"
        case "TOG": return "train.side.front.car.fill"
        case "METRO": return "tram.fill"
        default: return "mappin"
        }
    }

    var themeColor: Color {
        switch normalizedType {
        case "BUS": return .orange
        case "TOG": return .red
        case "METRO": return .blue
        default: return .gray
        }
    }

    var themeGradient: LinearGradient {
        switch normalizedType {
        case "BUS":
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "TOG":
            return LinearGradient(colors: [Color(red: 0.8, green: 0.1, blue: 0.1), .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "METRO":
            return LinearGradient(colors: [.blue, Color(red: 0.1, green: 0.1, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.gray, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var typeLabel: String {
        switch normalizedType {
        case "BUS": return "BUS"
        case "TOG": return "TOG"
        case "METRO": return "METRO"
        default: return "STATION"
        }
    }

    private var normalizedType: String {
        (stationType ?? "UNKNOWN").uppercased()
    }
}
