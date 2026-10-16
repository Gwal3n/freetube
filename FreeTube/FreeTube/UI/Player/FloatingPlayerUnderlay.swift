import SwiftUI

/// Lives inside a TabView page, below the native tab bar. The root player still supplies the
/// interactive surface above the bar; this only fills the portion seen through its glass.
@available(iOS 17.0, *)
struct FloatingPlayerUnderlay: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.floatingPlayerUnderlayLayout) private var layout

    var body: some View {
        GeometryReader { proxy in
            if layout.isVisible {
                let origin = proxy.frame(in: .global).origin
                FloatingPlayerVideoLayer(player: player.player)
                    .frame(width: layout.frameInGlobal.width, height: layout.frameInGlobal.height)
                    .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                    .mask(alignment: .topLeading) {
                        let hiddenHeight = min(layout.frameInGlobal.height,
                            max(0, layout.tabBarTopInGlobal - layout.frameInGlobal.minY))
                        Rectangle()
                            .frame(width: layout.frameInGlobal.width,
                                   height: layout.frameInGlobal.height - hiddenHeight)
                            .offset(y: hiddenHeight)
                    }
                    .position(
                        x: layout.frameInGlobal.midX - origin.x,
                        y: layout.frameInGlobal.midY - origin.y
                    )
                    .opacity(layout.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
