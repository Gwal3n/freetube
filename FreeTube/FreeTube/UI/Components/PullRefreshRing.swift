import SwiftUI
import UIKit

/// Replaces the native refresh spinner of a `.refreshable` scroll view with
/// `PullRefreshRingView`, drawn inside the system refresh control so it keeps the native
/// position. UIKit commits at a private distance, so the ring would not match it; this starts
/// the same refresh control itself once the ring is full. Draws nothing in SwiftUI.
@available(iOS 17.0, *)
struct PullRefreshRing: UIViewRepresentable {
    enum Placement {
        /// The ring is placed inside the refreshable scroll view's content.
        case enclosingScrollView
        /// The ring is placed beside the refreshable scroll view (e.g. a List's background).
        case adjacentScrollView
    }

    static let triggerDistance: CGFloat = 90

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
        private var observation: NSKeyValueObservation?
        private let ring = PullRefreshRingView()
        /// Top inset without the refresh control: while refreshing, UIKit adds the control's
        /// height to the inset, which would otherwise read the still-open gap as zero pull.
        private var restingTopInset: CGFloat?
        /// One trigger per pull; rearmed once the scroll view returns to its top edge.
        private var hasTriggered = false
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
            if control.tintColor != .clear { control.tintColor = .clear }
            if ring.superview !== control { control.addSubview(ring) }
            let transform = CGAffineTransform(translationX: 0, y: topOffset)
            if control.transform != transform { control.transform = transform }

            if !control.isRefreshing || restingTopInset == nil {
                restingTopInset = scrollView.adjustedContentInset.top
            }
            let pull = max(0, -(scrollView.contentOffset.y + (restingTopInset ?? 0)))
            ring.frame = CGRect(x: control.bounds.midX - 14, y: control.bounds.midY - 14, width: 28, height: 28)

            if control.isRefreshing {
                isSettling = true
            } else if pull < 1 {
                isSettling = false
                if !scrollView.isDragging { hasTriggered = false }
            }

            if !hasTriggered, !control.isRefreshing, scrollView.isDragging,
               pull >= PullRefreshRing.triggerDistance {
                hasTriggered = true
                control.beginRefreshing()
                control.sendActions(for: .valueChanged)
            }

            if control.isRefreshing {
                ring.update(progress: 1, isRefreshing: true)
            } else {
                let progress = isSettling ? 0 : min(1, pull / PullRefreshRing.triggerDistance)
                ring.update(progress: progress, isRefreshing: false)
            }
        }

        private func attachIfNeeded() {
            guard window != nil, scrollView == nil else { return }
            guard let target = findScrollView() else {
                // SwiftUI installs the refresh control lazily; retry briefly.
                guard attachAttempts < 10 else { return }
                attachAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attachIfNeeded()
                }
                return
            }
            scrollView = target
            observation = target.observe(\.contentOffset, options: [.initial]) { [weak self] _, _ in
                // contentOffset only changes on the main thread.
                MainActor.assumeIsolated { self?.update() }
            }
        }

        private func detach() {
            observation = nil
            scrollView = nil
            restingTopInset = nil
            hasTriggered = false
            isSettling = false
        }

        private func findScrollView() -> UIScrollView? {
            switch placement {
            case .enclosingScrollView:
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView {
                        return scrollView.refreshControl == nil ? nil : scrollView
                    }
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
