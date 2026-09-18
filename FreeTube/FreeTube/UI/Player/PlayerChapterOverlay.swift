import SwiftUI

/// Narrow observation boundary for the chapter panel's playback-position updates.
///
/// The chapter list highlights the active chapter from `elapsed`, which changes continuously.
/// Reading it here prevents those ticks from invalidating the complete expanded-player hierarchy.
@available(iOS 17.0, *)
struct PlayerChapterOverlay: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isLandscape: Bool
    let usesOLEDBackground: Bool
    let onInteraction: () -> Void

    var body: some View {
        ChapterListPanel(
            chapters: player.chapters,
            elapsed: player.elapsed,
            isLandscape: isLandscape,
            usesOLEDBackground: usesOLEDBackground,
            onSeek: { target in
                player.seek(to: target)
                onInteraction()
            },
            onDismiss: {
                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                    player.chapterListPresented = false
                }
            }
        )
    }
}
