import SwiftUI
import AVKit
import UIKit

/// AVPlayerViewController remains the video/PiP engine. Its native playback chrome is hidden in
/// favour of `CustomPlayerControls`, while the underlying controller still owns rendering and PiP.
@available(iOS 17.0, *)
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let pipDismissalRequest: Int
    let holdForSpeedEnabled: Bool
    let holdSpeedRate: Double
    let effectivePlaybackRate: Double
    var onHoldSpeedChange: (Double?) -> Double
    var onSeekRelative: (TimeInterval) -> Void
    var onSeekAbsolute: (TimeInterval) -> Void
    var onSeekPreview: (TimeInterval?) -> Void
    var onTogglePlayback: () -> Void
    var onToggleControls: () -> Void
    var onRestoreFromPictureInPicture: () -> Void
    var showsControls: Bool = false
    var entersPiPAutomatically: Bool = true
    var isInteractionEnabled: Bool = true
    var isZoomEnabled = false
    var onZoomPinch: (CGFloat, CGPoint, UIGestureRecognizer.State) -> Void = { _, _, _ in }
    var onZoomPan: (CGSize, UIGestureRecognizer.State) -> Void = { _, _ in }

    func makeCoordinator() -> PlayerGestureCoordinator {
        PlayerGestureCoordinator(
            player: player,
            pipDismissalRequest: pipDismissalRequest,
            holdForSpeedEnabled: holdForSpeedEnabled,
            holdSpeedRate: holdSpeedRate,
            effectivePlaybackRate: effectivePlaybackRate,
            onHoldSpeedChange: onHoldSpeedChange,
            onSeekRelative: onSeekRelative,
            onSeekAbsolute: onSeekAbsolute,
            onSeekPreview: onSeekPreview,
            onTogglePlayback: onTogglePlayback,
            onToggleControls: onToggleControls,
            onRestoreFromPictureInPicture: onRestoreFromPictureInPicture
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.canStartPictureInPictureAutomaticallyFromInline = entersPiPAutomatically
        controller.allowsPictureInPicturePlayback = true
        controller.allowsVideoFrameAnalysis = false
        controller.view.isUserInteractionEnabled = isInteractionEnabled
        controller.view.accessibilityElementsHidden = !isInteractionEnabled
        // Force the hierarchy to load before asking for `contentOverlayView`.
        _ = controller.view
        context.coordinator.isZoomEnabled = isZoomEnabled
        context.coordinator.onZoomPinch = onZoomPinch
        context.coordinator.onZoomPan = onZoomPan
        context.coordinator.install(on: controller)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.canStartPictureInPictureAutomaticallyFromInline = entersPiPAutomatically
        controller.allowsVideoFrameAnalysis = false
        // SwiftUI's `.allowsHitTesting(false)` does not always propagate through a
        // UIViewControllerRepresentable. Disable the native root in floating mode too, so
        // only its SwiftUI chrome accepts touches and navigation beneath remains responsive.
        controller.view.isUserInteractionEnabled = isInteractionEnabled
        controller.view.accessibilityElementsHidden = !isInteractionEnabled
        context.coordinator.isZoomEnabled = isZoomEnabled
        context.coordinator.onZoomPinch = onZoomPinch
        context.coordinator.onZoomPan = onZoomPan
        context.coordinator.dismissPiPIfRequested(
            on: controller,
            request: pipDismissalRequest
        )
        context.coordinator.update(
            player: player,
            holdForSpeedEnabled: holdForSpeedEnabled,
            holdSpeedRate: holdSpeedRate,
            effectivePlaybackRate: effectivePlaybackRate,
            onHoldSpeedChange: onHoldSpeedChange,
            onSeekRelative: onSeekRelative,
            onSeekAbsolute: onSeekAbsolute,
            onSeekPreview: onSeekPreview,
            onTogglePlayback: onTogglePlayback,
            onToggleControls: onToggleControls,
            onRestoreFromPictureInPicture: onRestoreFromPictureInPicture
        )
        context.coordinator.install(on: controller)
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: PlayerGestureCoordinator
    ) {
        coordinator.uninstall()
        controller.delegate = nil
    }
}
