import CoreGraphics

/// Presentation choices for thumbnails shown while dragging the player's timeline.
enum SeekPreviewStyle: String, CaseIterable, Identifiable {
    case compact
    case large
    case off

    var id: String { rawValue }

    var maximumWidth: CGFloat {
        switch self {
        case .compact, .off: 116
        case .large: 172
        }
    }

    var maximumHeight: CGFloat {
        switch self {
        case .compact, .off: 96
        case .large: 128
        }
    }

    var storyboardTileMaximumWidth: Int {
        switch self {
        case .compact, .off: 320
        case .large: 480
        }
    }

    var storyboardTileMaximumHeight: Int {
        switch self {
        case .compact, .off: 180
        case .large: 270
        }
    }
}
