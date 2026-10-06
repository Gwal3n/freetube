import SwiftUI

/// Controls above the *same* video surface used by the expanded player. The blank middle is a
/// large expand target; corner buttons remain visible without obscuring the picture.
@available(iOS 17.0, *)
struct FloatingMiniPlayerChrome: View {
    static let scrollClearance: CGFloat = 216 * 9 / 16 + 26

    @Environment(PlayerStateManager.self) private var player

    let actionsEnabled: Bool
    let onExpand: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Button {
                guard actionsEnabled else { return }
                onExpand()
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand player")

            VStack(spacing: 0) {
                HStack {
                    cornerButton(
                        player.hasEnded ? "arrow.counterclockwise" : player.isPlaying ? "pause.fill" : "play.fill",
                        accessibilityLabel: player.hasEnded ? "Replay" : player.isPlaying ? "Pause" : "Play"
                    ) {
                        player.togglePlayPause()
                    }
                    Spacer(minLength: 0)
                    cornerButton("xmark", accessibilityLabel: "Close player", action: onDismiss)
                }
                .padding(5)

                Spacer(minLength: 0)

                MiniPlayerProgress()
                    .background(.black.opacity(0.45))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cornerButton(
        _ symbol: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard actionsEnabled else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.6), in: Circle())
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
