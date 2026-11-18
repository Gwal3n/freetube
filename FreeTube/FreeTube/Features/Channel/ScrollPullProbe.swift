import SwiftUI
import UIKit

/// Reports how far the enclosing vertical scroll view is rubber-banded past its top edge.
/// SwiftUI scroll geometry did not deliver those negative offsets during a refresh drag on
/// device, so this observes the backing `UIScrollView` directly. It draws nothing.
///
/// UIKit's refresh control commits at a private distance, so custom pull feedback could not
/// match it. Instead this starts the existing refresh control at `triggerDistance` itself.
@available(iOS 17.0, *)
struct ScrollPullProbe: UIViewRepresentable {
    let triggerDistance: CGFloat
    let onPullChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.triggerDistance = triggerDistance
        view.onPullChange = onPullChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.triggerDistance = triggerDistance
        view.onPullChange = onPullChange
    }

    final class ProbeView: UIView {
        var triggerDistance: CGFloat = .infinity
        var onPullChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastPull: CGFloat = 0
        /// One trigger per pull; rearmed once the page returns to its top edge.
        private var hasTriggered = false
        /// Top inset without the refresh control: while refreshing, UIKit adds the control's
        /// height to the inset, which would otherwise read the still-open gap as zero pull.
        private var restingTopInset: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            guard let scrollView = ancestor as? UIScrollView else { return }
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                // contentOffset only changes on the main thread.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if scrollView.refreshControl?.isRefreshing != true || self.restingTopInset == nil {
                        self.restingTopInset = scrollView.adjustedContentInset.top
                    }
                    let inset = self.restingTopInset ?? scrollView.adjustedContentInset.top
                    let pull = max(0, -(scrollView.contentOffset.y + inset))
                    self.report(pull.rounded())
                    self.triggerRefreshIfNeeded(scrollView, pull: pull)
                }
            }
        }

        private func triggerRefreshIfNeeded(_ scrollView: UIScrollView, pull: CGFloat) {
            guard let refreshControl = scrollView.refreshControl else { return }
            if pull < 1, !scrollView.isDragging, !refreshControl.isRefreshing {
                hasTriggered = false
                return
            }
            guard !hasTriggered, scrollView.isDragging, pull >= triggerDistance,
                  !refreshControl.isRefreshing else { return }
            hasTriggered = true
            refreshControl.beginRefreshing()
            refreshControl.sendActions(for: .valueChanged)
        }

        private func report(_ pull: CGFloat) {
            guard pull != lastPull else { return }
            lastPull = pull
            onPullChange?(pull)
        }
    }
}
