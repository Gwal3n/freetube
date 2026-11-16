import CoreGraphics

/// Presentation choices for thumbnails shown while dragging the player's timeline.
enum SeekPreviewStyle: String, CaseIterable, Identifiable {
    case compact
    case large
    case off

    var id: String { rawValue }

    var maximumWidth: CGFloat {
        switch self {
        case .compact, .off: 160
        case .large: 232
        }
    }

    var maximumHeight: CGFloat {
        switch self {
        case .compact, .off: 120
        case .large: 168
        }
    }

    var storyboardTileMaximumWidth: Int {
        switch self {
        case .compact, .off: 480
        case .large: 640
        }
    }

    var storyboardTileMaximumHeight: Int {
        switch self {
        case .compact, .off: 270
        case .large: 360
        }
    }
}
