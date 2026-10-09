import Foundation

/// Which one-finger vertical interaction owns the fullscreen video's surface.
enum PlayerVerticalSwipeAction: String, CaseIterable, Identifiable {
    case fullscreen
    case adjustPlayback
    case off

    var id: String { rawValue }
}
