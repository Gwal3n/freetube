import SwiftUI
import UIKit

/// The app's allowed interface orientations. With the portrait lock on, browsing stays portrait;
/// the expanded player can always rotate for fullscreen viewing.
enum OrientationPolicy {
    static let lockKey = "portraitOrientationLock"

    private static var isLocked = false
    private static var playerExpanded = false
    private static let log = AppLog(subsystem: "com.leshko.freetube", category: "Orientation")

    static var supportedOrientations: UIInterfaceOrientationMask {
        isLocked && !playerExpanded ? .portrait : .all
    }

    /// Re-queries the allowed orientations and returns a sideways interface to portrait once
    /// only portrait is allowed, e.g. when the lock is enabled or the player collapses.
    static func update(isLocked: Bool, playerExpanded: Bool) {
        guard isLocked != self.isLocked || playerExpanded != self.playerExpanded else { return }
        self.isLocked = isLocked
        self.playerExpanded = playerExpanded
        log.info("Orientation policy locked=\(isLocked, privacy: .public) playerExpanded=\(playerExpanded, privacy: .public)")
        refresh()
    }

    /// Also called when a root sheet closes, since its controller no longer owns orientation.
    static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            // UIKit takes orientations from the topmost presented controller (e.g. the Settings
            // sheet where the lock is toggled), so every controller in each chain is refreshed.
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            if supportedOrientations == .portrait, scene.interfaceOrientation != .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

/// Supplies `OrientationPolicy` to UIKit; the app has no other delegate responsibilities.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Orientation")

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        let orientations = OrientationPolicy.supportedOrientations
        log.debug("Supported orientations requested: \(orientations.rawValue, privacy: .public)")
        return orientations
    }
}
