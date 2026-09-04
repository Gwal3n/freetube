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
    private var onSeekAbsolute: (TimeInterval) -> Void
    private var onSeekPreview: (TimeInterval?) -> Void
    private var onTogglePlayback: () -> Void
    private var onToggleControls: () -> Void
    private var gestures: [UIGestureRecognizer] = []
    private var continuationTapGesture: UITapGestureRecognizer?
    private var twoFingerTapGesture: UITapGestureRecognizer?
    private var singleTapGesture: UITapGestureRecognizer?
    private var horizontalPanGesture: UIPanGestureRecognizer?
    private var feedbackLabel: UILabel?
    private var outlinedFeedbackLabel: UILabel?
    private var feedbackWorkItem: DispatchWorkItem?
    private var pendingSingleTapWorkItem: DispatchWorkItem?
    private var seekSessionWorkItem: DispatchWorkItem?
    private var seekSessionTotal: TimeInterval = 0
    private var horizontalSeekStart: TimeInterval?
    private var horizontalSeekTarget: TimeInterval?
    private var horizontalSeekDuration: TimeInterval?
    private var horizontalSeekPeakVelocity: CGFloat = 0
    private var rateBeforeBoost: Float?
    private var lastPiPDismissalRequest: Int
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerGestures")

    init(
        player: AVPlayer,
        pipDismissalRequest: Int,
        onSeekRelative: @escaping (TimeInterval) -> Void,
        onSeekAbsolute: @escaping (TimeInterval) -> Void,
        onSeekPreview: @escaping (TimeInterval?) -> Void,
        onTogglePlayback: @escaping () -> Void,
        onToggleControls: @escaping () -> Void
    ) {
        self.player = player
        self.lastPiPDismissalRequest = pipDismissalRequest
        self.onSeekRelative = onSeekRelative
        self.onSeekAbsolute = onSeekAbsolute
        self.onSeekPreview = onSeekPreview
        self.onTogglePlayback = onTogglePlayback
        self.onToggleControls = onToggleControls
    }

    /// AVPlayerViewController owns the automatic PiP controller privately. Temporarily disabling
    /// PiP is its public way to close that presentation when the inline player is explicitly
    /// reopened; eligibility is restored on the following main-actor turn for future backgrounds.
    func dismissPiPIfRequested(on controller: AVPlayerViewController, request: Int) {
        guard request != lastPiPDismissalRequest else { return }
        lastPiPDismissalRequest = request
        controller.allowsPictureInPicturePlayback = false
        Task { @MainActor [weak self, weak controller] in
            try? await Task.sleep(for: .milliseconds(250))
            guard self?.lastPiPDismissalRequest == request else { return }
            controller?.allowsPictureInPicturePlayback = true
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    func update(
        player: AVPlayer,
        onSeekRelative: @escaping (TimeInterval) -> Void,
        onSeekAbsolute: @escaping (TimeInterval) -> Void,
        onSeekPreview: @escaping (TimeInterval?) -> Void,
        onTogglePlayback: @escaping () -> Void,
        onToggleControls: @escaping () -> Void
    ) {
        self.player = player
        self.onSeekRelative = onSeekRelative
        self.onSeekAbsolute = onSeekAbsolute
        self.onSeekPreview = onSeekPreview
        self.onTogglePlayback = onTogglePlayback
        self.onToggleControls = onToggleControls
    }

    func install(on controller: AVPlayerViewController) {
        guard let rootView = controller.view,
              let overlay = controller.contentOverlayView else { return }
        guard gestureView !== rootView else { return }
        uninstall()
        gestureView = rootView
        feedbackView = overlay

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

        let horizontalPan = UIPanGestureRecognizer(target: self, action: #selector(didPanHorizontally(_:)))
        horizontalPan.maximumNumberOfTouches = 1
        horizontalPan.cancelsTouchesInView = false
        horizontalPan.delegate = self

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(didTwoFingerTap(_:)))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.cancelsTouchesInView = false
        twoFingerTap.delaysTouchesEnded = false
        twoFingerTap.delegate = self

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didPrimaryTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        singleTap.delaysTouchesEnded = false
        singleTap.delegate = self
        singleTap.require(toFail: longPress)
        singleTap.require(toFail: horizontalPan)

        continuationTapGesture = continuationTap
        twoFingerTapGesture = twoFingerTap
        singleTapGesture = singleTap
        horizontalPanGesture = horizontalPan
        gestures = [continuationTap, longPress, horizontalPan, twoFingerTap, singleTap]
        gestures.forEach { rootView.addGestureRecognizer($0) }
        deferNativeSingleTaps(in: rootView, until: [singleTap, continuationTap, longPress, horizontalPan])
        // AVKit may finish installing its private control hierarchy after `makeUIViewController`
        // returns. Re-scan on the next main-actor turn so those late recognizers get the same
        // failure dependency.
        Task { @MainActor [weak self, weak rootView, weak singleTap, weak longPress, weak horizontalPan] in
            await Task.yield()
            guard let self, let rootView, let singleTap, let longPress, let horizontalPan else { return }
            guard let continuationTap = self.continuationTapGesture else { return }
            self.deferNativeSingleTaps(
                in: rootView,
                until: [singleTap, continuationTap, longPress, horizontalPan]
            )
        }
        log.info("Installed tap, hold, and horizontal-seek gestures on AVPlayerViewController root view")
    }

    func uninstall() {
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
        pendingSingleTapWorkItem?.cancel()
        pendingSingleTapWorkItem = nil
        endSeekSession(hideFeedback: false)
        restorePlaybackRateIfNeeded()
        if let gestureView {
            gestures.forEach { gestureView.removeGestureRecognizer($0) }
        }
        gestures.removeAll()
        continuationTapGesture = nil
        twoFingerTapGesture = nil
        singleTapGesture = nil
        horizontalPanGesture = nil
        resetHorizontalSeek()
        feedbackLabel?.removeFromSuperview()
        feedbackLabel = nil
        outlinedFeedbackLabel?.removeFromSuperview()
        outlinedFeedbackLabel = nil
        feedbackView = nil
        gestureView = nil
    }

    @objc private func didPrimaryTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        if let pendingSingleTapWorkItem {
            pendingSingleTapWorkItem.cancel()
            self.pendingSingleTapWorkItem = nil
            performDoubleTapSeek(at: gesture.location(in: gestureView))
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingSingleTapWorkItem = nil
            self?.onToggleControls()
        }
        pendingSingleTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func performDoubleTapSeek(at location: CGPoint) {
        guard let view = gestureView,
              let itemDuration = player?.currentItem?.duration.seconds,
              itemDuration.isFinite,
              itemDuration > 0 else { return }
        let isForward = location.x >= view.bounds.midX
        let interval: TimeInterval = isForward ? 10 : -10
        log.info("Double tap recognized; seeking \(interval, privacy: .public)s")
        onSeekRelative(interval)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        beginSeekSession(with: interval, isForward: isForward)
    }

    @objc private func didTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        log.info("Two-finger tap recognized; toggling playback")
        onTogglePlayback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            doubleTapFeedbackText(isForward: isForward),
            horizontalFraction: isForward ? 0.82 : 0.18,
            outlined: true,
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

    @objc private func didPanHorizontally(_ gesture: UIPanGestureRecognizer) {
        guard let view = gestureView else { return }

        switch gesture.state {
        case .began:
            endSeekSession(hideFeedback: false)
            restorePlaybackRateIfNeeded()
            guard let player else { return }
            let current = player.currentTime().seconds
            let duration = player.currentItem?.duration.seconds ?? .nan
            guard current.isFinite, duration.isFinite, duration > 0 else {
                resetHorizontalSeek()
                return
            }
            horizontalSeekStart = min(max(current, 0), duration)
            horizontalSeekTarget = horizontalSeekStart
            horizontalSeekDuration = duration
            horizontalSeekPeakVelocity = 0
            onSeekPreview(horizontalSeekStart)
        case .changed:
            guard let start = horizontalSeekStart,
                  let duration = horizontalSeekDuration,
                  view.bounds.width > 0 else { return }
            let translation = gesture.translation(in: view).x
            let sensitivity: TimeInterval
            if duration >= 3_600 {
                sensitivity = 120
            } else if duration >= 1_800 {
                sensitivity = 90
            } else {
                sensitivity = 60
            }
            horizontalSeekPeakVelocity = max(
                horizontalSeekPeakVelocity,
                abs(gesture.velocity(in: view).x)
            )
            // Slow drags retain the base scale for precise positioning. Faster swipes smoothly
            // increase that range up to 3×, while peak velocity keeps the preview from snapping
            // backwards merely because the finger decelerates before release.
            let velocityBoost = min(
                max((TimeInterval(horizontalSeekPeakVelocity) - 300) / 1_200, 0),
                2
            )
            let dragFraction = TimeInterval(translation / view.bounds.width)
            let target = min(
                max(start + dragFraction * sensitivity * (1 + velocityBoost), 0),
                duration
            )
            horizontalSeekTarget = target
            onSeekPreview(target)
            showFeedback(
                horizontalSeekText(offset: target - start),
                horizontalFraction: 0.5,
                verticalFraction: 0.10,
                compact: true,
                wide: true,
                automaticallyHide: false
            )
        case .ended:
            if let target = horizontalSeekTarget, horizontalSeekStart != nil {
                log.info("Horizontal swipe recognized; seeking to \(target, privacy: .public)s")
                onSeekAbsolute(target)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onSeekPreview(nil)
            resetHorizontalSeek()
            hideFeedback()
        case .cancelled, .failed:
            onSeekPreview(nil)
            resetHorizontalSeek()
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

    private func beginSeekSession(with interval: TimeInterval, isForward: Bool) {
        seekSessionTotal = interval
        // Once the initial double tap succeeds, count every following tap individually. Keeping
        // the double-tap recognizer enabled would make taps three and four trigger both recognizers.
        singleTapGesture?.isEnabled = false
        continuationTapGesture?.isEnabled = true
        showFeedback(
            doubleTapFeedbackText(isForward: isForward),
            horizontalFraction: isForward ? 0.82 : 0.18,
            outlined: true,
            automaticallyHide: false
        )
        scheduleSeekSessionEnd()
    }

    private func scheduleSeekSessionEnd() {
        seekSessionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.endSeekSession(hideFeedback: true)
        }
        seekSessionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func endSeekSession(hideFeedback: Bool) {
        seekSessionWorkItem?.cancel()
        seekSessionWorkItem = nil
        seekSessionTotal = 0
        continuationTapGesture?.isEnabled = false
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

    private func doubleTapFeedbackText(isForward: Bool) -> String {
        isForward ? "\(seekFeedbackText)  ≫" : "≪  \(seekFeedbackText)"
    }

    private func horizontalSeekText(offset: TimeInterval) -> String {
        let seconds = Int(abs(offset).rounded())
        guard seconds > 0 else { return "0 seconds" }
        let sign = offset > 0 ? "+" : "−"
        return "\(sign)\(seconds) \(seconds == 1 ? "second" : "seconds")"
    }

    private func resetHorizontalSeek() {
        horizontalSeekStart = nil
        horizontalSeekTarget = nil
        horizontalSeekDuration = nil
        horizontalSeekPeakVelocity = 0
    }

    private func showFeedback(
        _ text: String,
        horizontalFraction: CGFloat,
        verticalFraction: CGFloat = 0.5,
        compact: Bool = false,
        wide: Bool = false,
        outlined: Bool = false,
        automaticallyHide: Bool = true
    ) {
        guard let view = feedbackView else { return }
        feedbackWorkItem?.cancel()

        let label: UILabel
        if outlined {
            label = outlinedFeedbackLabel ?? makeOutlinedFeedbackLabel(in: view)
            feedbackLabel?.alpha = 0
        } else {
            label = feedbackLabel ?? makeFeedbackLabel(in: view)
            outlinedFeedbackLabel?.alpha = 0
        }
        let font: UIFont = outlined
            ? .systemFont(ofSize: 20, weight: .bold)
            : compact
            ? .preferredFont(forTextStyle: .subheadline)
            : .preferredFont(forTextStyle: .headline)
        label.font = font
        label.text = text
        label.bounds.size = outlined
            ? CGSize(width: 104, height: 38)
            : wide
            ? compact
                ? CGSize(width: 124, height: 26)
                : CGSize(width: 150, height: 38)
            : compact
                ? CGSize(width: 52, height: 26)
                : CGSize(width: 68, height: 38)
        label.layer.cornerRadius = outlined ? 0 : compact ? 13 : 19
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

    /// Double-tap feedback deliberately has its own label. Reusing the capsule label caused its
    /// outlined styling to leak into the 2× and horizontal-seek notices on later gestures.
    private func makeOutlinedFeedbackLabel(in view: UIView) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = .clear
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.95
        label.layer.shadowRadius = 1.5
        label.layer.shadowOffset = .zero
        label.isUserInteractionEnabled = false
        label.accessibilityElementsHidden = true
        view.addSubview(label)
        outlinedFeedbackLabel = label
        return label
    }

    private func hideFeedback() {
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.feedbackLabel?.alpha = 0
            self?.outlinedFeedbackLabel?.alpha = 0
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

    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.15
        }
    }
}
