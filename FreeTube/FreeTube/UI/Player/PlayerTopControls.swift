import SwiftUI

/// Configurable controls rendered at the top-right of the video surface. This view owns only
/// presentation; playback, orientation, and preference mutations stay with `FullScreenPlayer`.
@available(iOS 17.0, *)
struct PlayerTopControls: View {
    @AppStorage("playerMoreMenuDividers") private var moreMenuDividersRaw = ""
    @AppStorage("customPlaybackSpeeds") private var savedRatesRaw = ""
    @State private var isEnteringCustomSpeed = false
    @State private var customSpeedText = ""

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
    let captionsModel: PlayerCaptionsModel
    let onSetPlaybackRate: (Double) -> Void
    let onSetPlaybackQuality: (VideoQuality) -> Void
    let onToggleLoop: () -> Void
    let onToggleMute: () -> Void
    let onToggleFullscreen: () -> Void
    let onToggleAutoplay: () -> Void
    let onToggleAudioOnly: () -> Void
    let onSetSleepTimer: (SleepTimerOption) -> Void
    let onShowTranscript: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controlsRow
            ScrollView(.horizontal) {
                controlsRow
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
        }
        .buttonStyle(.plain)
        .alert("Custom speed", isPresented: $isEnteringCustomSpeed) {
            TextField("Speed", text: $customSpeedText)
                .keyboardType(.decimalPad)
            Button("Set Speed") {
                if let rate = PlaybackSpeedPresets.parse(customSpeedText) {
                    onSetPlaybackRate(rate)
                }
            }
            .disabled(PlaybackSpeedPresets.parse(customSpeedText) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter 0.25× to 2×, with up to two decimal places.")
        }
    }

    /// Keep the familiar single row when it fits. With more controls than a narrow video can
    /// show, the same ordered row scrolls rather than clipping controls or rewriting preferences.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            ForEach(controls) { control in
                controlView(control)
            }
            if !overflowControls.isEmpty {
                Menu {
                    ForEach(overflowControls) { control in
                        if control != overflowControls.first,
                           dividerAnchors.contains(control) {
                            Divider()
                        }
                        overflowItem(control)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .playerTopControl()
                }
                .accessibilityLabel("More player controls")
            }
        }
    }

    private var dividerAnchors: Set<PlayerTopControl> {
        PlayerTopControl.decodeMenuDividers(moreMenuDividersRaw)
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
        case .captions:
            captionsMenu(onPlayer: true)
        case .sleepTimer:
            Menu {
                sleepTimerChoices
            } label: {
                Image(systemName: "moon.zzz")
                    .playerTopControl()
                    .opacity(sleepTimerOption == .off ? 0.72 : 1)
            }
            .accessibilityLabel("Sleep timer")
            .accessibilityValue(sleepTimerOption == .off ? "Off" : "On")
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
        case .sleepTimer:
            sleepTimerMenu
        case .captions:
            captionsMenu(onPlayer: false)
        }
    }

    private func captionsMenu(onPlayer: Bool) -> some View {
        Menu {
            captionChoices
        } label: {
            if onPlayer {
                Image(systemName: captionsModel.selectedTrackID == nil
                    ? "captions.bubble" : "captions.bubble.fill")
                    .playerTopControl()
            } else {
                Label("Captions", systemImage: "captions.bubble")
            }
        }
        .accessibilityLabel("Captions")
    }

    @ViewBuilder
    private var captionChoices: some View {
        Button {
            captionsModel.select(nil)
        } label: {
            if captionsModel.selectedTrackID == nil {
                Label("Off", systemImage: "checkmark")
            } else {
                Text("Off")
            }
        }

        if captionsModel.isLoadingTracks {
            Button {} label: {
                Label("Loading captions…", systemImage: "hourglass")
            }
            .disabled(true)
        } else if captionsModel.hasTrackError {
            Button("Retry captions") { captionsModel.retryTracks() }
        } else if !captionsModel.hasLoadedTracks {
            Button("Load captions") { captionsModel.retryTracks() }
        } else if captionsModel.tracks.isEmpty {
            Button("No captions available") {}
                .disabled(true)
        } else {
            ForEach(captionsModel.tracks) { track in
                Button {
                    captionsModel.select(track)
                } label: {
                    if captionsModel.selectedTrackID == track.id {
                        Label {
                            Text(verbatim: track.displayName)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: track.displayName)
                    }
                }
            }
        }
        if captionsModel.isLoadingCues {
            Button {} label: {
                Label("Loading captions…", systemImage: "hourglass")
            }
            .disabled(true)
        } else if captionsModel.hasCueError {
            Button("Retry captions") { captionsModel.retrySelectedTrack() }
        }
        if captionsModel.selectedTrackID != nil {
            Divider()
            Button(action: onShowTranscript) {
                Label("View transcript", systemImage: "text.magnifyingglass")
            }
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
            sleepTimerChoices
        } label: {
            Label("Sleep timer", systemImage: "moon.zzz")
        }
    }

    @ViewBuilder
    private var sleepTimerChoices: some View {
        sleepTimerChoice(.off, title: "Off")
        sleepTimerChoice(.fifteenMinutes, title: "15 minutes")
        sleepTimerChoice(.thirtyMinutes, title: "30 minutes")
        sleepTimerChoice(.oneHour, title: "1 hour")
        sleepTimerChoice(.endOfVideo, title: "End of current video")
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

    @ViewBuilder
    private var speedChoices: some View {
        ForEach(availableSpeedRates, id: \.self) { rate in
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
        Divider()
        Button("Custom speed…") {
            customSpeedText = playbackRate.formatted(.number.precision(.fractionLength(0...2)))
            isEnteringCustomSpeed = true
        }
    }

    private var availableSpeedRates: [Double] {
        Array(Set(PlaybackSpeedPresets.quickRates + PlaybackSpeedPresets.decode(savedRatesRaw))).sorted()
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
        PlaybackSpeedPresets.label(rate)
    }
}
