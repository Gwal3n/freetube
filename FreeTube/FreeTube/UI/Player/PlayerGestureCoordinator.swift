import AVFoundation
import AVKit
import OSLog
import UIKit

/// Installs YouTube-style gestures on `AVPlayerViewController.view` while using its
/// `contentOverlayView` only for feedback. Native controls, AirPlay, PiP, and accessibility remain.
@available(iOS 17.0, *)
@MainActor
final class PlayerGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var player: AVPlayer?
    private weak var gestureView: UIView?
    private weak var feedbackView: UIView?
    private var onSeekRelative: (TimeInterval) -> Void
    private var gestures: [UIGestureRecognizer] = []
    private var feedbackLabel: UILabel?
    private var feedbackWorkItem: DispatchWorkItem?
    private var rateBeforeBoost: Float?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerGestures")

    init(player: AVPlayer, onSeekRelative: @escaping (TimeInterval) -> Void) {
        self.player = player
        self.onSeekRelative = onSeekRelative
    }

    func update(player: AVPlayer, onSeekRelative: @escaping (TimeInterval) -> Void) {
        self.player = player
        self.onSeekRelative = onSeekRelative
    }

    func install(on controller: AVPlayerViewController) {
        guard let rootView = controller.view,
              let overlay = controller.contentOverlayView else { return }
        guard gestureView !== rootView else { return }
        uninstall()
        gestureView = rootView
        feedbackView = overlay

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delaysTouchesEnded = false
        doubleTap.delegate = self

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = self

        gestures = [doubleTap, longPress]
        gestures.forEach { rootView.addGestureRecognizer($0) }
        deferNativeSingleTaps(in: rootView, until: doubleTap)
        // AVKit may finish installing its private control hierarchy after `makeUIViewController`
        // returns. Re-scan on the next main-actor turn so those late recognizers get the same
        // failure dependency.
        Task { @MainActor [weak self, weak rootView, weak doubleTap] in
            await Task.yield()
            guard let self, let rootView, let doubleTap else { return }
            self.deferNativeSingleTaps(in: rootView, until: doubleTap)
        }
        log.info("Installed double-tap and hold gestures on AVPlayerViewController root view")
    }

    func uninstall() {
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
        restorePlaybackRateIfNeeded()
        if let gestureView {
            gestures.forEach { gestureView.removeGestureRecognizer($0) }
        }
        gestures.removeAll()
        feedbackLabel?.removeFromSuperview()
        feedbackLabel = nil
        feedbackView = nil
        gestureView = nil
    }

    @objc private func didDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gestureView else { return }
        let isForward = gesture.location(in: view).x >= view.bounds.midX
        let interval: TimeInterval = isForward ? 10 : -10
        log.info("Double tap recognized; seeking \(interval, privacy: .public)s")
        onSeekRelative(interval)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFeedback(isForward ? "+10s" : "−10s", horizontalFraction: isForward ? 0.72 : 0.28)
    }

    @objc private func didLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let player,
                  player.currentItem?.status == .readyToPlay,
                  player.timeControlStatus != .paused else { return }
            rateBeforeBoost = player.rate > 0 ? player.rate : player.defaultRate
            player.rate = 2
            log.info("Hold recognized; temporary rate=2x")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showFeedback("2×", horizontalFraction: 0.5, automaticallyHide: false)
        case .ended, .cancelled, .failed:
            restorePlaybackRateIfNeeded()
            log.info("Hold ended; restored playback rate")
            hideFeedback()
        default:
            break
        }
    }

    private func restorePlaybackRateIfNeeded() {
        guard let priorRate = rateBeforeBoost else { return }
        rateBeforeBoost = nil
        guard let player, player.timeControlStatus != .paused else { return }
        player.rate = priorRate
    }

    private func showFeedback(
        _ text: String,
        horizontalFraction: CGFloat,
        automaticallyHide: Bool = true
    ) {
        guard let view = feedbackView else { return }
        feedbackWorkItem?.cancel()

        let label = feedbackLabel ?? makeFeedbackLabel(in: view)
        label.text = text
        label.center = CGPoint(x: view.bounds.width * horizontalFraction, y: view.bounds.midY)
        label.alpha = 1

        guard automaticallyHide else { return }
        let workItem = DispatchWorkItem { [weak self] in self?.hideFeedback() }
        feedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: workItem)
    }

    private func makeFeedbackLabel(in view: UIView) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        label.layer.cornerRadius = 22
        label.clipsToBounds = true
        label.bounds.size = CGSize(width: 76, height: 44)
        label.isUserInteractionEnabled = false
        label.accessibilityElementsHidden = true
        view.addSubview(label)
        feedbackLabel = label
        return label
    }

    private func hideFeedback() {
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.feedbackLabel?.alpha = 0
        }
    }

    /// Delays AVKit's tap-to-toggle-controls recognizer just long enough to determine whether the
    /// user is double tapping. If our recognizer succeeds, the native single tap fails and controls
    /// stay hidden; if there is only one tap, AVKit proceeds normally after the short delay.
    private func deferNativeSingleTaps(
        in rootView: UIView,
        until doubleTap: UITapGestureRecognizer
    ) {
        var deferredCount = 0
        var pendingViews = [rootView]

        while let view = pendingViews.popLast() {
            pendingViews.append(contentsOf: view.subviews)
            guard !(view is UIControl) else { continue }

            for case let nativeTap as UITapGestureRecognizer in view.gestureRecognizers ?? [] {
                guard nativeTap !== doubleTap,
                      nativeTap.numberOfTapsRequired == 1,
                      nativeTap.numberOfTouchesRequired == 1 else { continue }
                nativeTap.require(toFail: doubleTap)
                deferredCount += 1
            }
        }

        if deferredCount > 0 {
            log.debug("Deferred \(deferredCount, privacy: .public) native single-tap recognizer(s)")
        }
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
