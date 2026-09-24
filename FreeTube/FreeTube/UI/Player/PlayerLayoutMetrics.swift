import UIKit

/// Read-only access to the window's safe-area insets for the expanded player, which lays out
/// edge-to-edge and so cannot read them from its own `GeometryReader`.
///
/// This used to also locate the live `UITabBar` by recursively walking the window's view hierarchy
/// and convert its frame, so the floating mini player could be positioned above it. The mini
/// player is the tab view's bottom accessory now and the system insets it, so that scan — and the
/// layout-time hierarchy walk it cost — is gone.
@MainActor
enum PlayerLayoutMetrics {
    static var safeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
    }
}
