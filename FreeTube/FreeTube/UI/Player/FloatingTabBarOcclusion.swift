import SwiftUI

/// The root-owned compact player sits above TabView so expanded playback can cover everything.
/// Hide only its part behind the native tab bar; the selected tab draws that part beneath the bar
/// using a passive layer of the same AVPlayer. No second player or item is created.
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
