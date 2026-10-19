import SwiftUI

enum PlayerScrubberColorMode: String {
    case standard
    case custom

    func color(customHex: String) -> Color {
        switch self {
        case .standard: .red
        case .custom: WatchIndicatorStyle.color(hex: customHex) ?? .red
        }
    }
}
