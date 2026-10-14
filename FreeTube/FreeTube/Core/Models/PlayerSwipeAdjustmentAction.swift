import SwiftUI

/// User-selected action for a one-finger vertical swipe on one half of the fullscreen video.
enum PlayerSwipeAdjustmentAction: String, CaseIterable, Identifiable {
    case brightness
    case volume
    case off

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .brightness: "Brightness"
        case .volume: "Player volume"
        case .off: "Off"
        }
    }
}
