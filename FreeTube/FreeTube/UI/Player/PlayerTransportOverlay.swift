import SwiftUI

/// Narrow observation boundary for playback values that change frequently.
///
/// Keeping elapsed time, duration, and timeline data here prevents their periodic updates from
/// invalidating the expanded player's metadata and lower panels. Layout and actions remain
/// supplied by `FullScreenPlayer`, so this component does not own presentation behavior.
@available(iOS 17.0, *)
struct PlayerTransportOverlay: View {
    @Environment(PlayerStateManager.self) private var player

    let isVisible: Bool
    let isPreparing: Bool
    let isSeekPreviewActive: Bool
    let previewElapsed: TimeInterval?
    let hasPrevious: Bool
    let hasNext: Bool
    let videoTitle: String
    let channelName: String
    let usesLandscapeLayout: Bool
    let showsCollapseButton: Bool
    let additionalTopControls: AnyView
    let topControlsSafeAreaPadding: CGFloat
    let bottomTimelinePadding: CGFloat
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSeekPreviewChanged: (TimeInterval?) -> Void
    let onShowChapters: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        CustomPlayerControls(
            isVisible: isVisible,
            isPreparing: isPreparing,
            isSeekPreviewActive: isSeekPreviewActive,
            isPlaying: player.isPlaying,
            hasEnded: player.hasEnded,
            elapsed: previewElapsed ?? player.elapsed,
            duration: player.duration,
            isLive: player.currentVideo?.isLive == true,
            sponsorSegments: player.sponsorBlockSegments,
            chapters: player.chapters,
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            videoTitle: videoTitle,
            channelName: channelName,
            usesLandscapeLayout: usesLandscapeLayout,
            showsCollapseButton: showsCollapseButton,
            additionalTopControls: additionalTopControls,
            topControlsSafeAreaPadding: topControlsSafeAreaPadding,
            bottomTimelinePadding: bottomTimelinePadding,
            onTogglePlayPause: onTogglePlayPause,
            onSeek: onSeek,
            onSeekPreviewChanged: onSeekPreviewChanged,
            onShowChapters: onShowChapters,
            onPrevious: onPrevious,
            onNext: onNext,
            onCollapse: onCollapse
        )
    }
}
