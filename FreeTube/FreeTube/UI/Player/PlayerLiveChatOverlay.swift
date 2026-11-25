import SwiftUI

/// Narrow wrapper so live-chat presentation state stays beside the chapter overlay pattern.
@available(iOS 17.0, *)
struct PlayerLiveChatOverlay: View {
    @Environment(PlayerStateManager.self) private var player

    let videoID: String
    let isLandscape: Bool
    @Binding var expansionProgress: CGFloat
    let expansionTravel: CGFloat

    var body: some View {
        LiveChatPanel(
            model: player.liveChatSession(for: videoID),
            isLandscape: isLandscape,
            expansionProgress: $expansionProgress,
            expansionTravel: expansionTravel,
            onDismiss: {
                // Only flip presentation. Expansion resets in FullScreenPlayer after removal.
                player.liveChatPresented = false
            }
        )
    }
}
