import AVFoundation
import AVKit
import OSLog
import UIKit

/// Installs YouTube-style gestures on `AVPlayerViewController.view` while using its
/// `contentOverlayView` only for gesture feedback. SwiftUI owns the visible playback controls.
@available(iOS 17.0, *)
@MainActor
final class PlayerGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var player: AVPlayer?
    private weak var gestureView: UIView?
    private weak var feedbackView: UIView?
    private var onSeekRelative: (TimeInterval) -> Void
    private var onToggleControls: () -> Void
    private var gestures: [UIGestureRecognizer] = []
    private var doubleTapGesture: UITapGestureRecognizer?
    private var continuationTapGesture: UITapGestureRecognizer?
    private var singleTapGesture: UITapGestureRecognizer?
    private var feedbackLabel: UILabel?
    private var feedbackWorkItem: DispatchWorkItem?
    private var seekSessionWorkItem: DispatchWorkItem?
    private var seekSessionTotal: TimeInterval = 0
    private var rateBeforeBoost: Float?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerGestures")

    init(
        player: AVPlayer,
        onSeekRelative: @escaping (TimeInterval) -> Void,
        onToggleControls: @escaping () -> Void
    ) {
        self.player = player
        self.onSeekRelative = onSeekRelative
        self.onToggleControls = onToggleControls
    }

    func update(
        player: AVPlayer,
        onSeekRelative: @escaping (TimeInterval) -> Void,
        onToggleControls: @escaping () -> Void
    ) {
        self.player = player
        self.onSeekRelative = onSeekRelative
        self.onToggleControls = onToggleControls
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

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: longPress)

        doubleTapGesture = doubleTap
        continuationTapGesture = continuationTap
        singleTapGesture = singleTap
        gestures = [doubleTap, continuationTap, longPress, singleTap]
        gestures.forEach { rootView.addGestureRecognizer($0) }
        deferNativeSingleTaps(in: rootView, until: [doubleTap, continuationTap, longPress])
        // AVKit may finish installing its private control hierarchy after `makeUIViewController`
        // returns. Re-scan on the next main-actor turn so those late recognizers get the same
        // failure dependency.
        Task { @MainActor [weak self, weak rootView, weak doubleTap, weak longPress] in
            await Task.yield()
            guard let self, let rootView, let doubleTap, let longPress else { return }
            guard let continuationTap = self.continuationTapGesture else { return }
            self.deferNativeSingleTaps(
                in: rootView,
                until: [doubleTap, continuationTap, longPress]
            )
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
        singleTapGesture = nil
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
        beginSeekSession(with: interval, horizontalFraction: isForward ? 0.82 : 0.18)
    }

    @objc private func didSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onToggleControls()
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
            horizontalFraction: isForward ? 0.82 : 0.18,
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
            showFeedback(
                "2×",
                horizontalFraction: 0.5,
                verticalFraction: 0.10,
                compact: true,
                automaticallyHide: false
            )
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
        singleTapGesture?.isEnabled = false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func endSeekSession(hideFeedback: Bool) {
        seekSessionWorkItem?.cancel()
        seekSessionWorkItem = nil
        seekSessionTotal = 0
        continuationTapGesture?.isEnabled = false
        doubleTapGesture?.isEnabled = true
        singleTapGesture?.isEnabled = true
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
        verticalFraction: CGFloat = 0.5,
        compact: Bool = false,
        automaticallyHide: Bool = true
    ) {
        guard let view = feedbackView else { return }
        feedbackWorkItem?.cancel()

        let label = feedbackLabel ?? makeFeedbackLabel(in: view)
        label.text = text
        label.font = compact
            ? .preferredFont(forTextStyle: .subheadline)
            : .preferredFont(forTextStyle: .headline)
        label.bounds.size = compact
            ? CGSize(width: 52, height: 26)
            : CGSize(width: 68, height: 38)
        label.layer.cornerRadius = compact ? 13 : 19
        label.center = CGPoint(
            x: view.bounds.width * horizontalFraction,
            y: view.bounds.height * verticalFraction
        )
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
        label.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        label.layer.cornerRadius = 19
        label.clipsToBounds = true
        label.bounds.size = CGSize(width: 68, height: 38)
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
    /// user is double tapping or holding. If one of our recognizers succeeds, the native single tap
    /// fails and controls stay hidden; an ordinary quick single tap still proceeds normally.
    private func deferNativeSingleTaps(
        in rootView: UIView,
        until customGestures: [UIGestureRecognizer]
    ) {
        var deferredCount = 0
        var pendingViews = [rootView]

        while let view = pendingViews.popLast() {
            pendingViews.append(contentsOf: view.subviews)
            guard !(view is UIControl) else { continue }

            for case let nativeTap as UITapGestureRecognizer in view.gestureRecognizers ?? [] {
                guard !customGestures.contains(where: { $0 === nativeTap }),
                      nativeTap.numberOfTapsRequired == 1,
                      nativeTap.numberOfTouchesRequired == 1 else { continue }
                customGestures.forEach { nativeTap.require(toFail: $0) }
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
