import SwiftUI
import UIKit

/// Compact, entirely SwiftUI player chrome displayed above the native tab bar.
@available(iOS 17.0, *)
struct SwiftUIMiniPlayer: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let thumbnail: UIImage?
    let onExpand: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryForeground)
                        .frame(width: MediaStyle.actionSize, height: 50)
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Close player")

                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        artwork
                            .frame(width: 72, height: 42)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentVideo?.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(primaryForeground)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(secondaryForeground)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(expandAccessibilityLabel)
                .accessibilityHint("Shows the full player")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .frame(width: MediaStyle.actionSize, height: 50)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .linear(duration: 0.07), value: player.isPlaying)
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 4)
            .frame(height: 56, alignment: .center)

            MiniPlayerProgress()
        }
        .background {
            if oledMiniPlayer {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black)
            } else if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 17))
            } else {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.13), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        if case .downloading = player.loadState {
            Image(systemName: "arrow.down.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(.quaternary)
        } else if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .clipped()
        } else {
            Image(systemName: "play.rectangle.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(.quaternary)
        }
    }

    private var subtitle: String {
        switch player.loadState {
        case .resolving:
            return "Preparing…"
        case .downloading(let progress, let phase):
            guard let progress else { return "Processing…" }
            let prefix = phase.map { "Downloading \($0)" } ?? "Downloading"
            return "\(prefix) \(Int(progress * 100))%"
        case .failed(let message):
            return message
        case .idle, .buffering, .readyToPlay:
            return player.currentVideo?.channelName ?? ""
        }
    }

    private var expandAccessibilityLabel: String {
        guard let title = player.currentVideo?.title, !title.isEmpty else {
            return "Expand player"
        }
        return "Expand player, \(title)"
    }

    private var primaryForeground: Color {
        oledMiniPlayer ? .white : .primary
    }

    private var secondaryForeground: Color {
        oledMiniPlayer ? .white.opacity(0.66) : .secondary
    }

}
