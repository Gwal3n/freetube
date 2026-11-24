import SwiftUI

/// Narrow observation boundary for the chapter panel's playback-position updates.
/// Reading it here prevents those ticks from invalidating the complete expanded-player hierarchy.
@available(iOS 17.0, *)
struct PlayerChapterOverlay: View {
    @Environment(PlayerStateManager.self) private var player

    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    let expansionTravel: CGFloat
    let onInteraction: () -> Void

    var body: some View {
        ChapterListPanel(
            chapters: player.chapters,
            elapsed: player.pendingSeekTarget ?? player.elapsed,
            usesCommunityChapters: player.usesCommunityChapters,
            storyboard: player.storyboard,
            duration: player.duration,
            isLandscape: isLandscape,
            expansionProgress: $expansionProgress,
            expansionTravel: expansionTravel,
            onSeek: { target in
                player.seek(to: target)
                onInteraction()
            },
            onDismiss: {
                // Animation is owned by the panel (X button vs drag-dismiss paths).
                player.chapterListPresented = false
            }
        )
    }
}
