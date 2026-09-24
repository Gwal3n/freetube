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
/// Layout is the same in `.inline` and `.expanded`. The system already resizes the capsule when
/// the tab bar minimises; changing our own hierarchy at that moment is what made the title jump.
/// A second line of text and a different artwork size are therefore not worth the reflow.
struct MiniPlayerAccessory: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let thumbnail: UIImage?

    private var isInline: Bool { placement == .inline }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    artwork
                        .frame(width: 32, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(player.currentVideo?.title ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { player.requestExpansion() }
                .highPriorityGesture(accessoryDrag)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryForeground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
            .padding(.vertical, 5)

            // Flush with the bottom of the accessory, not overlaid on the title. Dropped when
            // the system has collapsed the capsule to a sliver — there is no room for it there.
            if !isInline {
                MiniPlayerProgress()
            }
        }
        .opacity(max(0, 1 - player.presentationProgress))
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: player.isPlaying)
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

    private var accessoryDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard player.presentationProgress < 0.98 else { return }
                let vertical = value.translation.height
                guard abs(vertical) > abs(value.translation.width) else { return }
                guard vertical < 0 else { return }
                if !player.presentationIsInteractive {
                    player.beginInteractivePresentation()
                }
                let travel = max(player.presentationTravel, 1)
                player.updatePresentationProgress(-vertical / travel)
            }
            .onEnded { value in
                if player.presentationIsInteractive {
                    player.endInteractivePresentation(velocity: value.velocity.height)
                    return
                }
                let vertical = value.translation.height
                guard abs(vertical) > abs(value.translation.width) else { return }
                if vertical > 36 {
                    player.dismiss()
                } else if vertical < -36 {
                    player.requestExpansion()
                }
            }
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            if case .downloading = player.loadState {
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .background(.quaternary)
            } else if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "play.rectangle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .background(.quaternary)
            }

            if isPreparingPlayback {
                PlaybackActivityIndicator(size: 12, lineWidth: 2)
                    .padding(3)
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

    private var expandAccessibilityLabel: String {
        guard let title = player.currentVideo?.title, !title.isEmpty else { return "Expand player" }
        return "Expand player, \(title)"
    }

    private var primaryForeground: Color { oledMiniPlayer ? .white : .primary }
}
