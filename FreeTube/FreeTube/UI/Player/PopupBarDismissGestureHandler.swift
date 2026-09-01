import UIKit

/// Adds swipe-to-dismiss to LNPopupUI's native bar without replacing its carefully styled content.
///
/// LNPopupUI already owns the bar's vertical pan for expanding the player. Horizontal swipes are
/// deliberately used here so dismissal does not compete with that gesture: either direction feels
/// like swiping the mini-player away, while an upward drag continues to open the full player.
@available(iOS 17.0, *)
@MainActor
final class PopupBarDismissGestureHandler: NSObject, UIGestureRecognizerDelegate {
    private weak var installedView: UIView?
    private var onDismiss: (() -> Void)?

    func install(on view: UIView, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        guard installedView !== view else { return }

        removeInstalledGestures()
        installedView = view

        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let gesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
            gesture.direction = direction
            gesture.delegate = self
            view.addGestureRecognizer(gesture)
        }
    }

    private func removeInstalledGestures() {
        installedView?.gestureRecognizers?
            .filter { $0.delegate === self }
            .forEach { installedView?.removeGestureRecognizer($0) }
    }

    @objc private func didSwipe() {
        onDismiss?()
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
