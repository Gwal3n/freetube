import SwiftUI
import UIKit

/// Moves the enclosing scroll view's native refresh control below the channel header, which is
/// drawn over the top of each page and would otherwise hide it. The control keeps its system
/// appearance, pull feedback, and trigger distance. It draws nothing itself.
@available(iOS 17.0, *)
struct RefreshControlPlacement: UIViewRepresentable {
    let topOffset: CGFloat

    func makeUIView(context: Context) -> PlacementView {
        let view = PlacementView()
        view.isUserInteractionEnabled = false
        view.topOffset = topOffset
        return view
    }

    func updateUIView(_ view: PlacementView, context: Context) {
        view.topOffset = topOffset
    }

    final class PlacementView: UIView {
        var topOffset: CGFloat = 0 {
            didSet { applyOffset() }
        }
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            guard let scrollView = ancestor as? UIScrollView else { return }
            self.scrollView = scrollView
            // SwiftUI installs the control lazily, so reapply as the page scrolls.
            observation = scrollView.observe(\.contentOffset, options: [.initial]) { [weak self] _, _ in
                // contentOffset only changes on the main thread.
                MainActor.assumeIsolated { self?.applyOffset() }
            }
        }

        private func applyOffset() {
            guard let refreshControl = scrollView?.refreshControl else { return }
            let transform = CGAffineTransform(translationX: 0, y: topOffset)
            if refreshControl.transform != transform {
                refreshControl.transform = transform
            }
        }
    }
}
