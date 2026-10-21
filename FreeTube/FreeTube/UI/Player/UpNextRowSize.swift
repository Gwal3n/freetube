import Foundation

/// Presentation size for recommendation rows beneath the player.
enum UpNextRowSize: String, CaseIterable, Identifiable {
    case compact
    case small
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .small: String(localized: "Small")
        case .large: String(localized: "Large")
        }
    }
}
