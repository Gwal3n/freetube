import SwiftUI

/// Keep the compact player's invisible portion from stealing touches from native tab items.
@available(iOS 17.0, *)
struct FloatingAboveTabBarHitRegion: Shape {
    let visibleHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: min(rect.height, max(0, visibleHeight))
        ))
    }
}
