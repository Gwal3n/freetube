import UIKit

/// Adds swipe-to-dismiss to LNPopupUI's native bar without replacing its carefully styled content.
///
/// LNPopupUI already owns the bar's upward pan for expanding the player. A downward swipe dismisses
/// it, matching the direction used to collapse the expanded popup while leaving upward drags free.
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

        let gesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe))
        gesture.direction = .down
        gesture.delegate = self
        view.addGestureRecognizer(gesture)
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
