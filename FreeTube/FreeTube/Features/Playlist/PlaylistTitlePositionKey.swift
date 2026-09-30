import SwiftUI

/// Reports the bottom of a playlist's visible title in its scroll view's coordinates.
/// An absent title means its List row has scrolled out of the mounted region.
@available(iOS 17.0, *)
struct PlaylistTitlePositionKey: PreferenceKey {
    static var defaultValue: CGFloat = -CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
