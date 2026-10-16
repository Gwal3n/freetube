import SwiftUI

/// Masks the floating video where the native tab bar begins. The player container must stay
/// above TabView for expanded playback, so z-order alone cannot put only its compact state
/// behind the tab bar. A short fade at the crossing avoids a hard cut while the drag continues
/// one-to-one beneath it.
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
                    if visibleHeight >= proxy.size.height {
                        Rectangle()
                    } else {
                        let fadeHeight = min(12, min(proxy.size.height - visibleHeight, visibleHeight))
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: max(0, 1 - fadeHeight / max(1, visibleHeight))),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: proxy.size.width, height: visibleHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    Rectangle()
                }
            }
        }
    }
}
