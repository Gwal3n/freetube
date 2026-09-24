import SwiftUI
import UIKit

/// The tab view's bottom accessory: compact player chrome that the system positions, shapes, and
/// glazes.
///
/// Nothing here draws a background, a capsule, a border, or a shadow. The accessory slot supplies
/// the Liquid Glass container, and painting our own inside it produces a second, slightly wrong
/// surface nested in the real one. The only exception is the OLED preference, which deliberately
/// replaces the glass with true black.
///
/// The system also owns the two behaviours this view used to implement by hand. It insets the
/// accessory above the tab bar, so there is no tab-bar frame to measure; and when the bar
/// minimises on scroll it re-lays the accessory inline between the active tab and the search
/// button, handing us `.inline` so the content can shed everything that no longer fits.
struct MiniPlayerAccessory: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let thumbnail: UIImage?

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: isInline ? 8 : 10) {
            artwork
                .frame(width: isInline ? 28 : 44, height: isInline ? 28 : 28)
                .clipShape(RoundedRectangle(cornerRadius: isInline ? 6 : 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentVideo?.title ?? "")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(primaryForeground)
                    .lineLimit(1)

                // Inline placement is a sliver between two tab-bar controls. A second line of
                // text there is unreadable before it is uninformative.
                if !isInline {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(primaryForeground)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            if !isInline {
                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
        }
        .padding(.leading, isInline ? 8 : 12)
        .padding(.trailing, 4)
        // Music's accessory has no progress line because a song's position is not something you
        // track at a glance. A video's is. It stays a child view so the half-second clock
        // invalidates only this hairline and not the artwork or the controls, and it is dropped
        // inline where there is no room for it.
        .overlay(alignment: .bottom) {
            if !isInline {
                MiniPlayerProgress()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 3)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: isInline)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: player.isPlaying)
        // The whole accessory expands the player, except where a control already claimed the tap.
        .contentShape(Rectangle())
        .onTapGesture { player.requestExpansion() }
        // Downward flick dismisses, matching the gesture the old floating bar had. Upward flick
        // expands, so both directions do the obvious thing rather than only one being live.
        .highPriorityGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    let vertical = value.translation.height
                    guard abs(vertical) > abs(value.translation.width) else { return }
                    if vertical > 0 {
                        player.dismiss()
                    } else {
                        player.requestExpansion()
                    }
                }
        )
        .background {
            if oledMiniPlayer {
                Rectangle().fill(Color.black)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(expandAccessibilityLabel)
        .accessibilityHint("Shows the full player")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            if case .downloading = player.loadState {
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .background(.quaternary)
            } else if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "play.rectangle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .background(.quaternary)
            }

            if isPreparingPlayback {
                PlaybackActivityIndicator(size: 14, lineWidth: 2)
                    .padding(4)
                    .background(.black.opacity(0.42), in: Circle())
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isPreparingPlayback)
    }

    private var isPreparingPlayback: Bool {
        switch player.loadState {
        case .resolving, .buffering: true
        case .idle, .downloading, .readyToPlay, .failed: false
        }
    }

    private var subtitle: String {
        switch player.loadState {
        case .resolving:
            "Preparing…"
        case .downloading(let progress, let phase):
            if let progress {
                "\(phase.map { "Downloading \($0)" } ?? "Downloading") \(Int(progress * 100))%"
            } else {
                "Processing…"
            }
        case .failed(let message):
            message
        case .idle, .buffering, .readyToPlay:
            player.currentVideo?.channelName ?? ""
        }
    }

    private var expandAccessibilityLabel: String {
        guard let title = player.currentVideo?.title, !title.isEmpty else { return "Expand player" }
        return "Expand player, \(title)"
    }

    private var primaryForeground: Color { oledMiniPlayer ? .white : .primary }
    private var secondaryForeground: Color { oledMiniPlayer ? .white.opacity(0.66) : .secondary }
}
