import SwiftUI

/// Masks the floating mini-player behind the tab bar; a passive AVPlayer layer fills the gap.
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
