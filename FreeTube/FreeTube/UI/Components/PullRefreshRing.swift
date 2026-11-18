import SwiftUI
import UIKit

private let log = AppLog(subsystem: "com.leshko.freetube", category: "PullRefresh")

/// The app's pull-to-refresh. `UIRefreshControl` commits to a refresh mid-drag and cannot be
/// talked out of it, so this observes the scroll view directly instead: the ring follows the
/// pull, a haptic marks crossing the threshold, and the refresh starts only if the finger
/// lifts beyond it. While refreshing, the gap is held open by extra top content inset.
@available(iOS 17.0, *)
struct PullRefreshRing: UIViewRepresentable {
    enum Placement {
        /// Attached inside the scroll view's content (e.g. a ScrollView page background).
        case enclosingScrollView
        /// Attached beside the scroll view (e.g. a List's background).
        case adjacentScrollView
    }

    static let triggerDistance: CGFloat = 110
    static let refreshingGap: CGFloat = 56
    /// Near-instant refreshes still spin briefly, so the ring doesn't flash and snap shut.
    static let minimumRefreshingDuration: Duration = .milliseconds(700)

    var placement: Placement = .adjacentScrollView
    /// Moves the ring down, for content whose top is covered by an overlay.
    var topOffset: CGFloat = 0
    /// When false the ring fades on release and the gap closes; the screen shows its own progress.
    var showsRefreshingIndicator = true
    let action: @Sendable () async -> Void

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        configure(view)
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        configure(view)
        view.update()
    }

    private func configure(_ view: AttachmentView) {
        view.placement = placement
        view.topOffset = topOffset
        view.showsRefreshingIndicator = showsRefreshingIndicator
        view.action = action
    }

    final class AttachmentView: UIView {
        /// Height of the large-title row that rides down with an overscrolled large title.
        private static let largeTitleHeight: CGFloat = 52

        var placement: Placement = .adjacentScrollView
        var topOffset: CGFloat = 0
        var showsRefreshingIndicator = true
        var action: (@Sendable () async -> Void)?
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private let ring = PullRefreshRingView()
        private let haptic = UIImpactFeedbackGenerator(style: .medium)
        private var isRefreshing = false
        /// The pull is past the threshold in the current drag.
        private var isArmed = false
        /// Hides the ring while the content settles back after a refresh ends.
        private var isSettling = false
        private var heldInset: CGFloat = 0
        private var baseContentInset: CGFloat = 0
        private var attachAttempts = 0
        private var validationTimer: Timer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            validationTimer?.invalidate()
            validationTimer = nil
            if window == nil {
                detach()
            } else {
                attachAttempts = 0
                attachIfNeeded()
                guard placement == .adjacentScrollView else { return }
                validationTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.validateAttachment() }
                }
            }
        }

        /// SwiftUI swaps content (e.g. a loading placeholder List for the results List) and the
        /// outgoing list can still be on top at attach time. Follow whichever list is current.
        private func validateAttachment() {
            guard window != nil, !isRefreshing, scrollView?.isDragging != true else { return }
            if let current = scrollView, current.window != nil {
                guard let found = findScrollView(), found !== current else { return }
            }
            if scrollView != nil { log.info("Watched list replaced; re-attaching") }
            detach()
            attachAttempts = 0
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        func update() {
            guard let scrollView else { return }
            if heldInset > 0, abs(scrollView.contentInset.top - (baseContentInset + heldInset)) > 0.5 {
                // SwiftUI rewrote the inset during a refresh; keep the gap open on top of it.
                baseContentInset = scrollView.contentInset.top
                scrollView.contentInset.top = baseContentInset + heldInset
            }
            let restingTop = scrollView.adjustedContentInset.top - heldInset
            // Content-space y of the top of the visible area below the bars; content starts at 0.
            let visibleTop = scrollView.contentOffset.y + restingTop
            let pull = max(0, -visibleTop)

            if scrollView.isDragging, !isRefreshing {
                if pull > Self.triggerHalf { haptic.prepare() }
                let armed = pull >= PullRefreshRing.triggerDistance
                if armed, !isArmed { haptic.impactOccurred() }
                isArmed = armed
            }

            if isRefreshing {
                if showsRefreshingIndicator { ring.update(progress: 1, isRefreshing: true) }
            } else if isSettling {
                // The ring is fading out; leave it alone until the content has settled.
                if pull < 1 { isSettling = false }
            } else {
                ring.update(progress: min(1, pull / PullRefreshRing.triggerDistance), isRefreshing: false)
            }
            guard pull > 0 || isRefreshing else { return }
            if ring.superview !== scrollView { scrollView.addSubview(ring) }
            if scrollView.subviews.last !== ring { scrollView.bringSubviewToFront(ring) }
            ring.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
            ring.center = CGPoint(
                x: scrollView.contentOffset.x + scrollView.bounds.width / 2,
                y: ringCenterY(in: scrollView, visibleTop: visibleTop, pull: pull)
            )
        }

        private static var triggerHalf: CGFloat { PullRefreshRing.triggerDistance / 2 }

        /// Centre of the gap between the bars (or covering overlay) and the content. An
        /// overscrolled large title moves down with the content, so there the gap opens above it.
        private func ringCenterY(in scrollView: UIScrollView, visibleTop: CGFloat, pull: CGFloat) -> CGFloat {
            if placement == .adjacentScrollView, let bar = navigationBar(for: scrollView) {
                let barBottom = scrollView.convert(bar.bounds, from: bar).maxY
                let stretch = barBottom - visibleTop
                if stretch > 0.5, stretch <= pull + 2 {
                    return visibleTop - Self.largeTitleHeight + stretch / 2
                }
            }
            return visibleTop / 2 + topOffset
        }

        private func navigationBar(for scrollView: UIScrollView) -> UINavigationBar? {
            var responder: UIResponder? = scrollView
            while let current = responder {
                if let controller = current as? UIViewController {
                    guard let bar = controller.navigationController?.navigationBar,
                          !bar.isHidden, bar.window != nil else { return nil }
                    return bar
                }
                responder = current.next
            }
            return nil
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended || pan.state == .cancelled || pan.state == .failed else { return }
            let shouldRefresh = isArmed && pan.state == .ended && !isRefreshing
            isArmed = false
            if shouldRefresh { beginRefresh() }
            update()
        }

        private func beginRefresh() {
            log.info("Released past threshold; refreshing")
            isRefreshing = true
            isSettling = true
            let showsIndicator = showsRefreshingIndicator
            if showsIndicator {
                applyHold()
            } else {
                ring.fadeOut()
            }
            let action = self.action
            Task { @MainActor [weak self] in
                let started = ContinuousClock.now
                await action?()
                if showsIndicator {
                    let remaining = PullRefreshRing.minimumRefreshingDuration - (ContinuousClock.now - started)
                    if remaining > .zero { try? await Task.sleep(for: remaining) }
                }
                self?.endRefresh()
            }
        }

        private func applyHold() {
            guard let scrollView, heldInset == 0 else { return }
            baseContentInset = scrollView.contentInset.top
            heldInset = PullRefreshRing.refreshingGap
            scrollView.contentInset.top = baseContentInset + heldInset
        }

        private func releaseHold(animated: Bool) {
            guard let scrollView, heldInset > 0 else {
                heldInset = 0
                return
            }
            heldInset = 0
            let changes = {
                scrollView.contentInset.top = self.baseContentInset
                let restingOffset = -scrollView.adjustedContentInset.top
                if !scrollView.isDragging, scrollView.contentOffset.y < restingOffset {
                    scrollView.contentOffset.y = restingOffset
                }
            }
            if animated {
                UIView.animate(
                    withDuration: 0.35,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                    animations: changes
                )
            } else {
                changes()
            }
        }

        private func endRefresh() {
            isRefreshing = false
            if showsRefreshingIndicator { ring.fadeOut() }
            releaseHold(animated: true)
            if let scrollView,
               scrollView.contentOffset.y + scrollView.adjustedContentInset.top > -1 {
                isSettling = false
            }
        }

        private func attachIfNeeded() {
            guard window != nil, scrollView == nil else { return }
            guard let target = findScrollView() else {
                // SwiftUI may still be building the scroll view; retry briefly.
                guard attachAttempts < 20 else { return }
                attachAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attachIfNeeded()
                }
                return
            }
            scrollView = target
            log.info("Attached to \(String(describing: type(of: target)), privacy: .public) height=\(Int(target.bounds.height), privacy: .public)")
            target.alwaysBounceVertical = true
            target.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            observation = target.observe(\.contentOffset, options: [.initial]) { [weak self] _, _ in
                // contentOffset only changes on the main thread.
                MainActor.assumeIsolated { self?.update() }
            }
            if isRefreshing { applyHold() }
        }

        private func detach() {
            releaseHold(animated: false)
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            ring.removeFromSuperview()
            observation = nil
            scrollView = nil
            isArmed = false
        }

        private func findScrollView() -> UIScrollView? {
            switch placement {
            case .enclosingScrollView:
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView { return scrollView }
                    ancestor = view.superview
                }
                return nil
            case .adjacentScrollView:
                // Other tabs' lists can live in the same hierarchy; only accept the list this
                // view is the background of, i.e. one whose on-screen frame contains it.
                // Hidden tabs' lists share this frame, so ask the window which list is actually
                // on top here, then require it to be a near relative of this background view.
                guard let window, bounds.width > 0, bounds.height > 0 else { return nil }
                let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
                var hit = window.hitTest(center, with: nil)
                var candidate: UIScrollView?
                while let view = hit {
                    if let scrollView = view as? UIScrollView, scrollView.bounds.height >= 200 {
                        candidate = scrollView
                        break
                    }
                    hit = view.superview
                }
                guard let candidate else { return nil }
                var ancestor = superview
                var depth = 0
                while let view = ancestor, depth < 4 {
                    if candidate.isDescendant(of: view) { return candidate }
                    ancestor = view.superview
                    depth += 1
                }
                return nil
            }
        }
    }
}

extension View {
    /// Pull-to-refresh with the app's ring; the action runs only after releasing past the threshold.
    @available(iOS 17.0, *)
    func pullToRefresh(
        showsRefreshingIndicator: Bool = true,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        background(
            PullRefreshRing(showsRefreshingIndicator: showsRefreshingIndicator, action: action)
                .allowsHitTesting(false)
        )
    }
}
