import SwiftUI
import UIKit

/// The app's allowed interface orientations. With the portrait lock on, browsing stays portrait;
/// the expanded player can always rotate for fullscreen viewing.
enum OrientationPolicy {
    static let lockKey = "portraitOrientationLock"

    private static var isLocked = false
    private static var playerExpanded = false

    static var supportedOrientations: UIInterfaceOrientationMask {
        isLocked && !playerExpanded ? .portrait : .all
    }

    /// Re-queries the allowed orientations and returns a sideways interface to portrait once
    /// only portrait is allowed, e.g. when the lock is enabled or the player collapses.
    static func update(isLocked: Bool, playerExpanded: Bool) {
        guard isLocked != self.isLocked || playerExpanded != self.playerExpanded else { return }
        self.isLocked = isLocked
        self.playerExpanded = playerExpanded
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if supportedOrientations == .portrait, scene.interfaceOrientation != .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

/// Supplies `OrientationPolicy` to UIKit; the app has no other delegate responsibilities.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationPolicy.supportedOrientations
    }
}
