import SwiftUI

/// Places the playlist dock and browser relative to the current video surface.
@available(iOS 17.0, *)
struct PlayerPlaylistPresentation: View {
    let size: CGSize
    let surfaceHeight: CGFloat
    let sidePanelWidth: CGFloat
    let isLandscape: Bool
    let usesPortraitFullscreen: Bool
    @Binding var isPresented: Bool
    @Binding var expansion: CGFloat
    let onOpenPlaylist: (String) -> Void

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if player.activePlaylist != nil, !usesPortraitFullscreen, !player.chapterListPresented {
            let dockHeight = 60 + PlayerLayoutMetrics.safeAreaInsets.bottom
            let browserTop = surfaceHeight * (1 - expansion)
            PlayerPlaylistPanel(
                isPresented: isPresented,
                isLandscape: isLandscape,
                expansionProgress: $expansion,
                expansionTravel: surfaceHeight,
                onOpen: {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        player.chapterListPresented = false
                        expansion = 0
                        isPresented = true
                    }
                },
                onDismiss: {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        isPresented = false
                        expansion = 0
                    }
                },
                onOpenPlaylist: onOpenPlaylist
            )
            .frame(
                width: isLandscape ? (isPresented ? sidePanelWidth : 46) : size.width,
                height: isLandscape
                    ? (isPresented ? size.height : 46)
                    : (isPresented ? max(0, size.height - browserTop) : dockHeight)
            )
            .offset(y: isLandscape
                ? (isPresented ? 0 : (size.height - 46) / 2)
                : (isPresented ? browserTop : size.height - dockHeight))
        }
    }
}
