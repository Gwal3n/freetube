import SwiftUI
import UIKit

/// Compact, entirely SwiftUI player chrome displayed above the native tab bar.
@available(iOS 17.0, *)
struct SwiftUIMiniPlayer: View {
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("oledPlayerBackground") private var oledPlayerBackground = false

    let thumbnail: UIImage?
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    player.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")

                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        artwork
                            .frame(width: 76, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentVideo?.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Expand player")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 4)
            .frame(height: 58)

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.red)
                    .frame(width: proxy.size.width * progress, height: 2)
            }
            .frame(height: 2)
        }
        .background {
            if oledPlayerBackground {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
            } else if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var progress: CGFloat {
        if case .downloading(let progress, _) = player.loadState {
            return CGFloat(min(1, max(0, progress ?? 0)))
        }
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, player.elapsed / player.duration)))
    }
}
