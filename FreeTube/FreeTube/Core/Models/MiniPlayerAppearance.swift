import Foundation

enum MiniPlayerAppearance: String, CaseIterable, Identifiable {
    case liquidGlass
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .oled: "OLED Black"
        }
    }
}
