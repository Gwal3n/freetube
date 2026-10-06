import SwiftUI

/// Reserves the floating player's resting height inside a scrolling screen's safe area. The
/// native tab bar already contributes its own inset. Keep this active while expanded too:
/// changing it mid-collapse
/// would make the underlying list jump during the interactive handoff.
@available(iOS 17.0, *)
struct MiniPlayerScrollClearance: ViewModifier {
    @Environment(PlayerStateManager.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.miniPlayerVisible {
                Color.clear
                    .frame(height: FloatingMiniPlayerChrome.scrollClearance)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
