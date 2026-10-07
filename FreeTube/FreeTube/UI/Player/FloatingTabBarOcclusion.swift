import SwiftUI

/// Clips the floating video at the native tab bar's top edge. The player container must stay
/// above TabView for expanded playback, so z-order alone cannot put only its compact state
/// behind the tab bar. This mask gives the same visual handoff during a downward drag.
@available(iOS 17.0, *)
struct FloatingTabBarOcclusion: ViewModifier {
    let tabBarTop: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                if isEnabled {
                    let visibleHeight = min(proxy.size.height,
                        max(0, tabBarTop - proxy.frame(in: .named("playerContainer")).minY))
                    Rectangle()
                        .frame(width: proxy.size.width, height: visibleHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Rectangle()
                }
            }
        }
    }
}
