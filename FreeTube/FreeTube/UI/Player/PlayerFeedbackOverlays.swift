import SwiftUI

/// Feedback rendered above the video surface while controls, seeking, or playback state change.
@available(iOS 17.0, *)
struct PlayerFeedbackOverlays: View {
    let isFloating: Bool
    let controlFrame: CGRect
    let timelineBottomPadding: CGFloat
    let surfaceSize: CGSize
    let collapseProgress: CGFloat
    let seekPreviewStyle: SeekPreviewStyle
    let scrubberSeekPreview: TimeInterval?
    let swipeAdjustment: PlayerSwipeAdjustmentModel

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsStatusOverlay: Bool {
        switch player.loadState {
        case .downloading, .failed:
            return true
        case .idle, .resolving, .buffering, .readyToPlay:
            return false
        }
    }

    @ViewBuilder
    var body: some View {
        // Long-running fallback downloads and failures retain their explanatory overlay.
        Group {
            if !isFloating && showsStatusOverlay {
                DownloadProgressOverlay(
                    state: player.loadState,
                    allowsRetry: player.currentVideo?.id.hasPrefix("fetch-") == false,
                    onRetry: { player.retryFailedPlayback() }
                )
                .opacity(max(0, 1 - collapseProgress * 2.5))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsStatusOverlay)

        if !isFloating,
           let preparation = player.fastPlaybackPreparation {
            FastPlaybackProgressOverlay(
                preparation: preparation,
                rate: player.playbackRate,
                onCancel: { player.cancelPendingFastPlayback() }
            )
            .position(
                x: controlFrame.midX,
                y: controlFrame.minY + min(72, max(52, controlFrame.height * 0.24))
            )
            .opacity(max(0, 1 - collapseProgress * 3))
            .allowsHitTesting(collapseProgress < 0.05)
            .zIndex(6)
        }

        if !isFloating, seekPreviewStyle != .off,
           let previewTime = scrubberSeekPreview {
            Group {
                if player.isAudioOnly {
                    AudioOnlySeekPreview(
                        artwork: player.currentArtwork,
                        thumbnailURL: player.currentVideo?.thumbnailURL,
                        previewTime: previewTime,
                        style: seekPreviewStyle
                    )
                } else if let tile = player.storyboard?.tile(
                    at: previewTime,
                    duration: player.duration,
                    maximumWidth: seekPreviewStyle.storyboardTileMaximumWidth,
                    maximumHeight: seekPreviewStyle.storyboardTileMaximumHeight
                ) {
                    StoryboardPreview(
                        tile: tile,
                        videoPresentationSize: player.videoPresentationSize,
                        previewTime: previewTime,
                        style: seekPreviewStyle
                    )
                }
            }
            .position(
                x: controlFrame.minX + PlayerViewportLayout.storyboardPreviewX(
                    time: previewTime,
                    duration: player.duration,
                    surfaceWidth: controlFrame.width,
                    previewWidth: seekPreviewStyle.maximumWidth
                ),
                y: max(
                    58 + (seekPreviewStyle.maximumHeight - 96) / 2,
                    // Align the preview time with the elapsed/duration row;
                    // the image above it stays clear of the timeline.
                    controlFrame.maxY
                        - timelineBottomPadding
                        - 84.5
                        - (seekPreviewStyle.maximumHeight - 96) / 2
                )
            )
            .allowsHitTesting(false)
            .zIndex(4)
        }

        if !isFloating, let notice = player.sponsorBlockNotice {
            SponsorBlockSkipOverlay(
                notice: notice,
                onUndo: { player.undoSponsorBlockSkip() },
                onSkip: { player.confirmSponsorBlockSkip() },
                onDismiss: { player.dismissSponsorBlockNotice() },
                bottomPadding: timelineBottomPadding + 46
            )
            .frame(width: controlFrame.width, height: controlFrame.height)
            .position(x: controlFrame.midX, y: controlFrame.midY)
            .opacity(max(0, 1 - collapseProgress * 2.5))
        }

        if !isFloating {
            PlayerSwipeAdjustmentOverlay(
                model: swipeAdjustment,
                surfaceSize: surfaceSize
            )
            .zIndex(7)
        }
    }
}
