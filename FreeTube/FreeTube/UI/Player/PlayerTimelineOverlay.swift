import SwiftUI

/// The playback-clock observation boundary. Keeping tick reads inside this leaf prevents
/// elapsed-time updates from rebuilding titles, top menus, and the play/pause morph hierarchy.
@available(iOS 17.0, *)
struct PlayerTimelineOverlay: View {
    @Environment(PlayerStateManager.self) private var player
    let previewElapsed: TimeInterval?
    let onSeek: (TimeInterval) -> Void
    let onPreviewChanged: (TimeInterval?) -> Void
    let onShowChapters: () -> Void

    var body: some View {
        SponsorBlockTimeline(
            elapsed: player.elapsed,
            previewElapsed: previewElapsed,
            duration: player.duration,
            isLive: player.currentVideo?.isLive == true,
            segments: player.sponsorBlockSegments,
            chapters: player.chapters,
            onSeek: onSeek,
            onPreviewChanged: onPreviewChanged,
            onShowChapters: onShowChapters
        )
    }
}
