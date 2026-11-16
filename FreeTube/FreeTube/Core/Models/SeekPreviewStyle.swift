import CoreGraphics

/// Presentation choices for thumbnails shown while dragging the player's timeline.
/// `compact` keeps its stored value for existing installs and is presented as Normal.
enum SeekPreviewStyle: String, CaseIterable, Identifiable {
    case small
    case compact
    case large
    case off

    var id: String { rawValue }

    var maximumWidth: CGFloat {
        switch self {
        case .small: 116
        case .compact, .off: 160
        case .large: 232
        }
    }

    var maximumHeight: CGFloat {
        switch self {
        case .small: 96
        case .compact, .off: 120
        case .large: 168
        }
    }

    var storyboardTileMaximumWidth: Int {
        switch self {
        case .small: 320
        case .compact, .off: 480
        case .large: 640
        }
    }

    var storyboardTileMaximumHeight: Int {
        switch self {
        case .small: 180
        case .compact, .off: 270
        case .large: 360
        }
    }
}
