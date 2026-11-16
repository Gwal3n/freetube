import SwiftUI
import UIKit

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
    @State private var seekPreviewLabelWidth: CGFloat?

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
                        chapterTitle: chapterTitle(at: previewTime),
                        style: seekPreviewStyle,
                        labelOffset: seekPreviewLabelOffset(at: previewTime),
                        onLabelWidthChange: { seekPreviewLabelWidth = $0 }
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
                        chapterTitle: chapterTitle(at: previewTime),
                        style: seekPreviewStyle,
                        labelOffset: seekPreviewLabelOffset(at: previewTime),
                        onLabelWidthChange: { seekPreviewLabelWidth = $0 }
                    )
                }
            }
            .position(
                x: controlFrame.minX + seekPreviewImageX(at: previewTime),
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

    /// The image follows the thumb to the surface edge.
    private func seekPreviewImageX(at time: TimeInterval) -> CGFloat {
        PlayerViewportLayout.storyboardPreviewX(
            time: time,
            duration: player.duration,
            surfaceWidth: controlFrame.width,
            previewWidth: seekPreviewStyle.maximumWidth
        )
    }

    /// The time line stops beside the elapsed and duration labels instead of covering them,
    /// expressed as an offset from the image's centre.
    private func seekPreviewLabelOffset(at time: TimeInterval) -> CGFloat {
        let labelX = PlayerViewportLayout.storyboardPreviewX(
            time: time,
            duration: player.duration,
            surfaceWidth: controlFrame.width,
            previewWidth: seekPreviewLabelWidth ?? seekPreviewStyle.maximumWidth,
            edgeClearance: timeLabelClearance
        )
        return labelX - seekPreviewImageX(at: time)
    }

    /// The timeline's horizontal inset, the widest time label, and a small gap. The duration is
    /// measured for both sides: elapsed never has more digits, and a fixed reserve keeps the
    /// preview from shifting as the clock ticks.
    private var timeLabelClearance: CGFloat {
        let duration = max(player.duration.isFinite ? player.duration : 0, 0)
        let total = Int(duration)
        let label = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
        let pointSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        let font = UIFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
        return 12 + ceil(labelWidth) + 6
    }

    private func chapterTitle(at time: TimeInterval) -> String? {
        player.chapters.last { $0.startTime <= time }?.title
    }
}
