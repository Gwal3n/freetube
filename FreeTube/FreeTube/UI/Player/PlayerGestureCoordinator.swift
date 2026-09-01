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
    private var doubleTapGesture: UITapGestureRecognizer?
    private var continuationTapGesture: UITapGestureRecognizer?
    private var feedbackLabel: UILabel?
    private var feedbackWorkItem: DispatchWorkItem?
    private var seekSessionWorkItem: DispatchWorkItem?
    private var seekSessionTotal: TimeInterval = 0
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

        let continuationTap = UITapGestureRecognizer(
            target: self,
            action: #selector(didContinueSeeking(_:))
        )
        continuationTap.numberOfTapsRequired = 1
        continuationTap.cancelsTouchesInView = false
        continuationTap.delaysTouchesEnded = false
        continuationTap.delegate = self
        continuationTap.isEnabled = false

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = self

        doubleTapGesture = doubleTap
        continuationTapGesture = continuationTap
        gestures = [doubleTap, continuationTap, longPress]
        gestures.forEach { rootView.addGestureRecognizer($0) }
        deferNativeSingleTaps(in: rootView, until: [doubleTap, continuationTap])
        // AVKit may finish installing its private control hierarchy after `makeUIViewController`
        // returns. Re-scan on the next main-actor turn so those late recognizers get the same
        // failure dependency.
        Task { @MainActor [weak self, weak rootView, weak doubleTap] in
            await Task.yield()
            guard let self, let rootView, let doubleTap else { return }
            guard let continuationTap = self.continuationTapGesture else { return }
            self.deferNativeSingleTaps(in: rootView, until: [doubleTap, continuationTap])
        }
        log.info("Installed double-tap and hold gestures on AVPlayerViewController root view")
    }

    func uninstall() {
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
        endSeekSession(hideFeedback: false)
        restorePlaybackRateIfNeeded()
        if let gestureView {
            gestures.forEach { gestureView.removeGestureRecognizer($0) }
        }
        gestures.removeAll()
        doubleTapGesture = nil
        continuationTapGesture = nil
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
        beginSeekSession(with: interval, horizontalFraction: isForward ? 0.72 : 0.28)
    }

    @objc private func didContinueSeeking(_ gesture: UITapGestureRecognizer) {
        guard let view = gestureView else { return }
        let isForward = gesture.location(in: view).x >= view.bounds.midX
        let interval: TimeInterval = isForward ? 10 : -10
        seekSessionTotal += interval
        log.info("Seek session tap; seeking \(interval, privacy: .public)s total=\(self.seekSessionTotal, privacy: .public)s")
        onSeekRelative(interval)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFeedback(
            seekFeedbackText,
            horizontalFraction: isForward ? 0.72 : 0.28,
            automaticallyHide: false
        )
        scheduleSeekSessionEnd()
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

    private func beginSeekSession(with interval: TimeInterval, horizontalFraction: CGFloat) {
        seekSessionTotal = interval
        // Once the initial double tap succeeds, count every following tap individually. Keeping
        // the double-tap recognizer enabled would make taps three and four trigger both recognizers.
        doubleTapGesture?.isEnabled = false
        continuationTapGesture?.isEnabled = true
        showFeedback(seekFeedbackText, horizontalFraction: horizontalFraction, automaticallyHide: false)
        scheduleSeekSessionEnd()
    }

    private func scheduleSeekSessionEnd() {
        seekSessionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.endSeekSession(hideFeedback: true)
        }
        seekSessionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func endSeekSession(hideFeedback: Bool) {
        seekSessionWorkItem?.cancel()
        seekSessionWorkItem = nil
        seekSessionTotal = 0
        continuationTapGesture?.isEnabled = false
        doubleTapGesture?.isEnabled = true
        if hideFeedback {
            self.hideFeedback()
        }
    }

    private var seekFeedbackText: String {
        let seconds = Int(abs(seekSessionTotal))
        if seekSessionTotal > 0 { return "+\(seconds)s" }
        if seekSessionTotal < 0 { return "−\(seconds)s" }
        return "0s"
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
        until customTaps: [UITapGestureRecognizer]
    ) {
        var deferredCount = 0
        var pendingViews = [rootView]

        while let view = pendingViews.popLast() {
            pendingViews.append(contentsOf: view.subviews)
            guard !(view is UIControl) else { continue }

            for case let nativeTap as UITapGestureRecognizer in view.gestureRecognizers ?? [] {
                guard !customTaps.contains(where: { $0 === nativeTap }),
                      nativeTap.numberOfTapsRequired == 1,
                      nativeTap.numberOfTouchesRequired == 1 else { continue }
                customTaps.forEach { nativeTap.require(toFail: $0) }
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
