import SwiftUI
import UIKit

private let log = AppLog(subsystem: "com.leshko.freetube", category: "PullRefresh")

/// Replaces the native refresh spinner of a `.refreshable` scroll view with
/// `PullRefreshRingView`, drawn inside the system refresh control so it keeps the native
/// position. UIKit still decides when the pull is far enough (and plays its haptic), but it
/// does so mid-drag; SwiftUI's refresh handlers are therefore detached from the control and
/// sent only once the finger lifts. Draws nothing in SwiftUI.
@available(iOS 17.0, *)
struct PullRefreshRing: UIViewRepresentable {
    enum Placement {
        /// The ring is placed inside the refreshable scroll view's content.
        case enclosingScrollView
        /// The ring is placed beside the refreshable scroll view (e.g. a List's background).
        case adjacentScrollView
    }

    /// Pull at which UIKit last committed to a refresh; the ring fills against this.
    @MainActor static var triggerDistance: CGFloat = 120

    var placement: Placement = .adjacentScrollView
    /// Moves the refresh control down, for content whose top is covered by an overlay.
    var topOffset: CGFloat = 0

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.placement = placement
        view.topOffset = topOffset
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        view.placement = placement
        view.topOffset = topOffset
        view.update()
    }

    final class AttachmentView: UIView {
        var placement: Placement = .adjacentScrollView
        var topOffset: CGFloat = 0
        private weak var scrollView: UIScrollView?
        private weak var control: UIRefreshControl?
        private var observation: NSKeyValueObservation?
        private let ring = PullRefreshRingView()
        /// Top inset without the refresh control: while refreshing, UIKit adds the control's
        /// height to the inset, which would otherwise read the still-open gap as zero pull.
        private var restingTopInset: CGFloat?
        private var heldActions: [UIAction] = []
        private var heldTargets: [(target: AnyObject, selector: Selector)] = []
        /// UIKit has committed to a refresh, waiting for the finger to lift.
        private var awaitingRelease = false
        private var wasDragging = false
        /// Hides the ring while the content settles back after a refresh ends.
        private var isSettling = false
        private var attachAttempts = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                detach()
            } else {
                attachAttempts = 0
                attachIfNeeded()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        func update() {
            guard let scrollView, let control = scrollView.refreshControl else { return }
            if control !== self.control {
                self.control = control
                heldActions = []
                heldTargets = []
                log.info("Attached to refresh control")
            }
            holdRefreshHandlers(of: control)
            if control.tintColor != .clear { control.tintColor = .clear }
            if ring.superview !== control { control.addSubview(ring) }
            let transform = CGAffineTransform(translationX: 0, y: topOffset)
            if control.transform != transform { control.transform = transform }

            if !control.isRefreshing || restingTopInset == nil {
                restingTopInset = scrollView.adjustedContentInset.top
            }
            let pull = max(0, -(scrollView.contentOffset.y + (restingTopInset ?? 0)))
            let isDragging = scrollView.isDragging
            ring.frame = CGRect(x: control.bounds.midX - 14, y: control.bounds.midY - 14, width: 28, height: 28)

            if control.isRefreshing, !awaitingRelease, isDragging, !isSettling {
                // UIKit just committed (and played its haptic). Hold the refresh until release.
                awaitingRelease = true
                if pull > 40 { PullRefreshRing.triggerDistance = pull }
            }
            if awaitingRelease, wasDragging, !isDragging {
                awaitingRelease = false
                sendHeldRefresh(from: control)
            }
            wasDragging = isDragging

            if control.isRefreshing, !awaitingRelease {
                isSettling = true
                ring.update(progress: 1, isRefreshing: true)
            } else if awaitingRelease {
                ring.update(progress: 1, isRefreshing: false)
            } else {
                if pull < 1 { isSettling = false }
                let progress = isSettling ? 0 : min(1, pull / PullRefreshRing.triggerDistance)
                ring.update(progress: progress, isRefreshing: false)
            }
        }

        /// SwiftUI may re-register its handler on updates, so this runs on every pass.
        private func holdRefreshHandlers(of control: UIRefreshControl) {
            var actions: [UIAction] = []
            var targets: [(target: AnyObject, selector: Selector)] = []
            control.enumerateEventHandlers { action, targetAction, event, _ in
                guard event.contains(.valueChanged) else { return }
                if let action {
                    actions.append(action)
                } else if let targetAction, let target = targetAction.0 {
                    targets.append((target as AnyObject, targetAction.1))
                }
            }
            guard !actions.isEmpty || !targets.isEmpty else { return }
            for action in actions {
                control.removeAction(action, for: .valueChanged)
            }
            for entry in targets {
                control.removeTarget(entry.target, action: entry.selector, for: .valueChanged)
            }
            heldActions = actions
            heldTargets = targets
        }

        private func sendHeldRefresh(from control: UIRefreshControl) {
            guard control.isRefreshing else { return }
            if heldActions.isEmpty, heldTargets.isEmpty {
                log.error("No refresh handler to send; ending refresh")
                control.endRefreshing()
                return
            }
            for action in heldActions {
                control.sendAction(action)
            }
            for entry in heldTargets {
                control.sendAction(entry.selector, to: entry.target, for: nil)
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
            // The refresh control can be installed after this; update() picks it up lazily.
            observation = target.observe(\.contentOffset, options: [.initial]) { [weak self] _, _ in
                // contentOffset only changes on the main thread.
                MainActor.assumeIsolated { self?.update() }
            }
        }

        private func detach() {
            observation = nil
            scrollView = nil
            restingTopInset = nil
            awaitingRelease = false
            wasDragging = false
            isSettling = false
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
                var ancestor = superview
                var depth = 0
                while let view = ancestor, depth < 4 {
                    if let scrollView = Self.refreshableScrollView(in: view) { return scrollView }
                    ancestor = view.superview
                    depth += 1
                }
                return nil
            }
        }

        private static func refreshableScrollView(in root: UIView) -> UIScrollView? {
            var queue = [root]
            var index = 0
            while index < queue.count, index < 400 {
                let view = queue[index]
                index += 1
                if let scrollView = view as? UIScrollView, scrollView.refreshControl != nil {
                    return scrollView
                }
                queue.append(contentsOf: view.subviews)
            }
            return nil
        }
    }
}

extension View {
    /// `.refreshable` with the app's pull-to-refresh ring instead of the system spinner.
    @available(iOS 17.0, *)
    func pullToRefresh(action: @escaping @Sendable () async -> Void) -> some View {
        refreshable(action: action)
            .background(PullRefreshRing().allowsHitTesting(false))
    }
}
