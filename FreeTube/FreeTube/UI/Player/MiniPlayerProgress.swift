import SwiftUI

/// Isolates the half-second playback observation from artwork and mini-player controls.
@available(iOS 17.0, *)
struct MiniPlayerProgress: View {
    @Environment(PlayerStateManager.self) private var player

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.red)
                .frame(width: proxy.size.width * progress, height: 2)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        if case .downloading(let progress, _) = player.loadState {
            return CGFloat(min(1, max(0, progress ?? 0)))
        }
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, player.elapsed / player.duration)))
    }
}
