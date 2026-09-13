import SwiftUI

/// Configurable controls rendered at the top-right of the video surface. This view owns only
/// presentation; playback, orientation, and preference mutations stay with `FullScreenPlayer`.
@available(iOS 17.0, *)
struct PlayerTopControls: View {
    let controls: [PlayerTopControl]
    let playbackRate: Double
    let isMuted: Bool
    let isLooping: Bool
    let isAutoplayEnabled: Bool
    let isFullscreen: Bool
    let onSetPlaybackRate: (Double) -> Void
    let onToggleLoop: () -> Void
    let onToggleMute: () -> Void
    let onToggleFullscreen: () -> Void
    let onToggleAutoplay: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(controls) { control in
                controlView(control)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func controlView(_ control: PlayerTopControl) -> some View {
        switch control {
        case .speed:
            speedMenu
        case .loop:
            Button(action: onToggleLoop) {
                Image(systemName: "repeat.1")
                    .playerTopControl()
                    .opacity(isLooping ? 1 : 0.58)
            }
            .accessibilityLabel("Loop video")
            .accessibilityValue(isLooping ? "On" : "Off")
        case .mute:
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .playerTopControl()
            }
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        case .fullscreen:
            Button(action: onToggleFullscreen) {
                Image(systemName: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .playerTopControl()
            }
            .accessibilityLabel(isFullscreen ? "Exit fullscreen" : "Enter fullscreen")
        case .autoplay:
            Button(action: onToggleAutoplay) {
                Image(systemName: isAutoplayEnabled ? "play.circle.fill" : "play.circle")
                    .playerTopControl()
                    .opacity(isAutoplayEnabled ? 1 : 0.58)
            }
            .accessibilityLabel("Autoplay next")
            .accessibilityValue(isAutoplayEnabled ? "On" : "Off")
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.5, 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button {
                    onSetPlaybackRate(rate)
                } label: {
                    if abs(playbackRate - rate) < 0.01 {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(rateLabel(playbackRate))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 42, minHeight: 36)
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
