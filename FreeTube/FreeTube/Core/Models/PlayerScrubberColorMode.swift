import SwiftUI

/// Player timeline and mini-player progress color. Independent of the app accent unless
/// `.accent` is chosen; thumbnail watch progress has its own separate preference.
enum PlayerScrubberColorMode: String {
    case standard
    case accent
    case custom

    func color(customHex: String, accent: AppAccentPreset, accentHex: String) -> Color {
        switch self {
        case .standard: .red
        case .accent: accent.color(customHex: accentHex)
        case .custom: WatchIndicatorStyle.color(hex: customHex) ?? .red
        }
    }
}
