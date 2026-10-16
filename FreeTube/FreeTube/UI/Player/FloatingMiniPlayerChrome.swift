import SwiftUI

/// Controls above the *same* video surface used by the expanded player. The blank middle is a
/// large expand target; corner buttons remain visible without obscuring the picture.
@available(iOS 17.0, *)
struct FloatingMiniPlayerChrome: View {
    static let cornerRadius: CGFloat = 14

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        accessibilityLabel: player.hasEnded ? "Replay" : player.isPlaying ? "Pause" : "Play",
                        action: { player.togglePlayPause() },
                        label: {
                            Group {
                                if player.hasEnded {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .bold))
                                } else {
                                    PlaybackMorphShape(progress: player.isPlaying ? 1 : 0)
                                        .fill(.white)
                                        .frame(width: 14, height: 14)
                                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: player.isPlaying)
                                }
                            }
                            .frame(width: 14, height: 14)
                        }
                    )
                    Spacer(minLength: 0)
                    cornerButton(
                        accessibilityLabel: "Close player",
                        action: onDismiss,
                        label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                        }
                    )
                }
                .padding(5)

                Spacer(minLength: 0)

                MiniPlayerProgress()
                    .background(.black.opacity(0.45))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private func cornerButton<Label: View>(
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            guard actionsEnabled else { return }
            action()
        } label: {
            label()
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
