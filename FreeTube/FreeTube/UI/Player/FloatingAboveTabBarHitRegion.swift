import SwiftUI

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
