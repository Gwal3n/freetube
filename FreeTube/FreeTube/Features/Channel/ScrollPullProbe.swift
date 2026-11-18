import SwiftUI
import UIKit

/// Reports how far the enclosing vertical scroll view is rubber-banded past its top edge.
/// SwiftUI scroll geometry did not deliver those negative offsets during a refresh drag on
/// device, so this observes the backing `UIScrollView` directly. It draws nothing.
@available(iOS 17.0, *)
struct ScrollPullProbe: UIViewRepresentable {
    let onPullChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onPullChange = onPullChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onPullChange = onPullChange
    }

    final class ProbeView: UIView {
        var onPullChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?
        private var lastPull: CGFloat = 0
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
                }
            }
        }

        private func report(_ pull: CGFloat) {
            guard pull != lastPull else { return }
            lastPull = pull
            onPullChange?(pull)
        }
    }
}
