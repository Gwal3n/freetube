import SwiftUI

/// Narrow observation boundary for playback values that change frequently.
///
/// Elapsed time and timeline data are observed only by the nested `PlayerTimelineOverlay`;
/// this boundary observes infrequent transport changes, not each playback tick. Layout and actions remain
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
            previewElapsed: previewElapsed,
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
