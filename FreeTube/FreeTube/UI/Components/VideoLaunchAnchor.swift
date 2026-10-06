import SwiftUI

/// Stores a thumbnail's current screen frame without invalidating its row on every scroll tick.
/// The frame is read only when that row is tapped to start a player presentation.
@available(iOS 17.0, *)
final class VideoLaunchAnchor {
    var frame: CGRect = .zero
}
