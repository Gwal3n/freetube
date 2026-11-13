import SwiftUI

@available(iOS 17.0, *)
struct FloatingPlayerUnderlay: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.floatingPlayerUnderlayLayout) private var layout

    var body: some View {
        GeometryReader { proxy in
            if layout.isVisible {
                let origin = proxy.frame(in: .global).origin
                ZStack {
                    FloatingPlayerVideoLayer(player: player.player)
                    // The root player covers the video with its thumbnail until the first
                    // frame is ready. Mirror that same artwork here so loading does not
                    PlayerArtworkBackdrop(
                        artwork: player.currentArtwork,
                        state: player.loadState,
                        isAudioOnly: player.isAudioOnly
                    )
                    .frame(width: layout.frameInGlobal.width, height: layout.frameInGlobal.height)
                    // Mirror the existing compact chrome below the tab bar so its corner
                    // controls and progress track continue with the video during a drag.
                    // The root-owned chrome remains the only interactive copy.
                    FloatingMiniPlayerChrome(
                        actionsEnabled: false,
                        onExpand: {},
                        onDismiss: {}
                    )
                }
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
