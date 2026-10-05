import SwiftUI

/// Configurable controls rendered at the top-right of the video surface. This view owns only
/// presentation; playback, orientation, and preference mutations stay with `FullScreenPlayer`.
@available(iOS 17.0, *)
struct PlayerTopControls: View {
    let controls: [PlayerTopControl]
    let overflowControls: [PlayerTopControl]
    let playbackRate: Double
    let playbackQuality: VideoQuality
    let isMuted: Bool
    let isLooping: Bool
    let isAutoplayEnabled: Bool
    let isFullscreen: Bool
    let isAudioOnly: Bool
    let isSwitchingAudioMode: Bool
    let sleepTimerOption: SleepTimerOption
    let onSetPlaybackRate: (Double) -> Void
    let onSetPlaybackQuality: (VideoQuality) -> Void
    let onToggleLoop: () -> Void
    let onToggleMute: () -> Void
    let onToggleFullscreen: () -> Void
    let onToggleAutoplay: () -> Void
    let onToggleAudioOnly: () -> Void
    let onSetSleepTimer: (SleepTimerOption) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(controls) { control in
                controlView(control)
            }
            Menu {
                ForEach(overflowControls) { control in
                    overflowItem(control)
                }
                if !overflowControls.isEmpty { Divider() }
                sleepTimerMenu
            } label: {
                Image(systemName: "ellipsis")
                    .playerTopControl()
            }
            .accessibilityLabel("More player controls")
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
        case .audioOnly:
            Button(action: onToggleAudioOnly) {
                Image(systemName: isAudioOnly ? "headphones.circle.fill" : "headphones")
                    .playerTopControl()
                    .opacity(isAudioOnly ? 1 : 0.72)
            }
            .disabled(isSwitchingAudioMode)
            .accessibilityLabel("Audio-only playback")
            .accessibilityValue(isSwitchingAudioMode ? "Switching" : (isAudioOnly ? "On" : "Off"))
        case .quality:
            Menu {
                qualityChoices
            } label: {
                Text(playbackQuality.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
            }
            .disabled(isAudioOnly)
            .accessibilityLabel("Quality limit")
            .accessibilityValue(playbackQuality.displayName)
        }
    }

    @ViewBuilder
    private func overflowItem(_ control: PlayerTopControl) -> some View {
        switch control {
        case .speed:
            Menu {
                speedChoices
            } label: {
                Label("Speed: \(rateLabel(playbackRate))", systemImage: control.systemImage)
            }
        case .quality:
            Menu {
                qualityChoices
            } label: {
                Label("Quality limit: \(playbackQuality.displayName)", systemImage: control.systemImage)
            }
            .disabled(isAudioOnly)
        case .loop:
            Button(action: onToggleLoop) {
                Label(isLooping ? "Turn loop off" : "Loop current video", systemImage: control.systemImage)
            }
        case .mute:
            Button(action: onToggleMute) {
                Label(isMuted ? "Unmute" : "Mute", systemImage: control.systemImage)
            }
        case .fullscreen:
            Button(action: onToggleFullscreen) {
                Label(isFullscreen ? "Exit fullscreen" : "Enter fullscreen", systemImage: control.systemImage)
            }
        case .autoplay:
            Button(action: onToggleAutoplay) {
                Label(isAutoplayEnabled ? "Turn autoplay off" : "Turn autoplay on", systemImage: control.systemImage)
            }
        case .audioOnly:
            Button(action: onToggleAudioOnly) {
                Label(isAudioOnly ? "Turn audio-only off" : "Turn audio-only on", systemImage: control.systemImage)
            }
            .disabled(isSwitchingAudioMode)
        }
    }

    private var speedMenu: some View {
        Menu {
            speedChoices
        } label: {
            Text(rateLabel(playbackRate))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(rateLabel(playbackRate))
    }

    private var sleepTimerMenu: some View {
        Menu {
            sleepTimerChoice(.off, title: "Off")
            sleepTimerChoice(.fifteenMinutes, title: "15 minutes")
            sleepTimerChoice(.thirtyMinutes, title: "30 minutes")
            sleepTimerChoice(.oneHour, title: "1 hour")
            sleepTimerChoice(.endOfVideo, title: "End of current video")
        } label: {
            Label("Sleep timer", systemImage: "moon.zzz")
        }
    }

    private func sleepTimerChoice(_ option: SleepTimerOption, title: LocalizedStringKey) -> some View {
        Button {
            onSetSleepTimer(option)
        } label: {
            if sleepTimerOption == option {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var speedChoices: some View {
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
    }

    private var qualityChoices: some View {
        Section("Preferred maximum") {
            ForEach(VideoQuality.allCases.filter { $0 != .audioOnly }) { quality in
                Button {
                    onSetPlaybackQuality(quality)
                } label: {
                    if playbackQuality == quality {
                        Label(quality.displayName, systemImage: "checkmark")
                    } else {
                        Text(quality.displayName)
                    }
                }
            }
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
