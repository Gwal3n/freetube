import SwiftUI

/// Narrow wrapper so live-chat presentation state stays beside the chapter overlay pattern.
@available(iOS 17.0, *)
struct PlayerLiveChatOverlay: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                    player.liveChatPresented = false
                }
            }
        )
    }
}
