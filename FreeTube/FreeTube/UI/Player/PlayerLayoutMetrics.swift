import UIKit

/// Read-only geometry bridge for system chrome that SwiftUI does not expose to an overlay.
/// No UIKit view is created or owned here; player presentation remains entirely SwiftUI.
@available(iOS 17.0, *)
@MainActor
enum PlayerLayoutMetrics {
    /// The container asks for this clearance on every interactive-drag frame. Keep only a weak
    /// reference to the native bar; its frame and visibility are still read live below.
    private static weak var cachedTabBar: UITabBar?

    static var safeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }

    static var bottomTabBarClearance: CGFloat {
        guard let window = keyWindow else { return 50 }
        guard let tabBar = visibleTabBar(in: window) else { return window.safeAreaInsets.bottom + 50 }
        let frame = tabBar.convert(tabBar.bounds, to: window)
        guard frame.width > window.bounds.width * 0.5,
              frame.maxY > window.bounds.height * 0.7 else {
            return window.safeAreaInsets.bottom + 50
        }
        return max(window.safeAreaInsets.bottom, window.bounds.height - frame.minY) + 6
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
    }

    private static func visibleTabBar(in window: UIWindow) -> UITabBar? {
        if let cachedTabBar,
           cachedTabBar.window === window,
           isVisible(cachedTabBar, in: window) {
            return cachedTabBar
        }
        let tabBar = firstVisibleTabBar(in: window)
        cachedTabBar = tabBar
        return tabBar
    }

    private static func firstVisibleTabBar(in view: UIView) -> UITabBar? {
        guard !view.isHidden, view.alpha > 0.01 else { return nil }
        if let tabBar = view as? UITabBar {
            return tabBar
        }
        for child in view.subviews {
            if let tabBar = firstVisibleTabBar(in: child) { return tabBar }
        }
        return nil
    }

    private static func isVisible(_ view: UIView, in window: UIWindow) -> Bool {
        var ancestor: UIView? = view
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            if current === window { return true }
            ancestor = current.superview
        }
        return false
    }
}
