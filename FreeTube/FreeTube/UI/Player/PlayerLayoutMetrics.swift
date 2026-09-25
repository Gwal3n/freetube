import UIKit

/// Read-only geometry bridge for system chrome that SwiftUI does not expose to an overlay.
/// No UIKit view is created or owned here; player presentation remains entirely SwiftUI.
@available(iOS 17.0, *)
@MainActor
enum PlayerLayoutMetrics {
    static var safeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }

    static var bottomTabBarClearance: CGFloat {
        guard let window = keyWindow,
              let tabBar = firstTabBar(in: window),
              !tabBar.isHidden,
              tabBar.alpha > 0.01 else {
            return safeAreaInsets.bottom + 50
        }
        let frame = tabBar.convert(tabBar.bounds, to: window)
        guard frame.width > window.bounds.width * 0.5,
              frame.maxY > window.bounds.height * 0.7 else {
            return safeAreaInsets.bottom + 50
        }
        let clearance = window.bounds.height - frame.minY
        // Ignore a converted frame that spans far more than a tab bar; using it
        // would position the mini-player outside the visible viewport.
        guard clearance > 0, clearance < 160 else {
            return safeAreaInsets.bottom + 50
        }
        return max(safeAreaInsets.bottom, clearance) + 6
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
    }

    private static func firstTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for child in view.subviews {
            if let tabBar = firstTabBar(in: child) { return tabBar }
        }
        return nil
    }
}
