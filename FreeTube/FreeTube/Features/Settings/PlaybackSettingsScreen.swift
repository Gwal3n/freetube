import SwiftUI

@available(iOS 17.0, *)
struct PlaybackSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("playbackSpeedChoices") private var savedPlaybackSpeedsRaw = ""
    @AppStorage("customPlaybackSpeeds") private var legacyCustomPlaybackSpeedsRaw = ""
    @AppStorage(HoldSpeedIndicatorStyle.storageKey) private var holdSpeedIndicatorStyleRaw = HoldSpeedIndicatorStyle.storedDefault
    @AppStorage(HoldSpeedIndicatorStyle.autoHideKey) private var holdSpeedIndicatorAutoHide = false
    @AppStorage(HoldSpeedIndicatorStyle.hideDelayKey) private var holdSpeedIndicatorHideDelay = HoldSpeedIndicatorStyle.defaultHideDelay
    @State private var showingHoldSpeedEditor = false
    @State private var holdSpeedText = ""
    @State private var showingHideDelayEditor = false
    @State private var hideDelayText = ""

    var body: some View {
        Form {
            Section {
                Picker("Default playback quality", selection: Bindable(model).preferredQuality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .settingsSearchRow("Default playback quality")
                Picker("Cellular streaming limit", selection: Bindable(model).cellularPlaybackQuality) {
                    Text("No extra limit").tag(VideoQuality.auto)
                    ForEach(VideoQuality.allCases.filter { $0 != .auto && $0 != .audioOnly }) { quality in
                        Text("Up to \(quality.displayName)").tag(quality)
                    }
                }
                .settingsSearchRow("Cellular streaming limit")
                .onChange(of: model.cellularPlaybackQuality) { _, _ in
                    player.refreshPlaybackQualityLimits()
                }
                NavigationLink {
                    CustomPlaybackSpeedsScreen(defaultPlaybackRate: Bindable(model).defaultPlaybackRate)
                } label: {
                    LabeledContent {
                        Text(verbatim: PlaybackSpeedPresets.label(model.defaultPlaybackRate))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Playback speeds", systemImage: "speedometer")
                    }
                }
                .settingsSearchRow("Playback speeds")
                .onChange(of: model.defaultPlaybackRate) { _, rate in
                    player.setPlaybackRate(rate)
                }
                .onChange(of: savedPlaybackSpeedsRaw) { _, _ in
                    if !defaultPlaybackRates.contains(model.defaultPlaybackRate) {
                        model.defaultPlaybackRate = 1
                    }
                }
                NavigationLink {
                    CustomSleepTimersScreen()
                } label: {
                    Label("Sleep timer durations", systemImage: "moon.zzz")
                }
                .settingsSearchRow("Sleep timer durations")
                Toggle("Hold for speed", isOn: Bindable(model).holdForSpeedEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Hold for speed")
                Button {
                    holdSpeedText = model.holdSpeedRate.formatted(.number.precision(.fractionLength(0...2)))
                    showingHoldSpeedEditor = true
                } label: {
                    LabeledContent("Hold speed") {
                        Text(verbatim: PlaybackSpeedPresets.label(model.holdSpeedRate))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.holdForSpeedEnabled)
                .settingsSearchRow("Hold speed")
                if model.holdForSpeedEnabled {
                    Picker("Speed indicator", selection: $holdSpeedIndicatorStyleRaw) {
                        ForEach(HoldSpeedIndicatorStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .settingsSearchRow("Speed indicator")
                    if holdSpeedIndicatorStyleRaw != HoldSpeedIndicatorStyle.none.rawValue {
                        Toggle("Hide speed indicator", isOn: $holdSpeedIndicatorAutoHide)
                            .tint(settingsToggleTint)
                            .settingsSearchRow("Hide speed indicator")
                        if holdSpeedIndicatorAutoHide {
                            Button {
                                hideDelayText = holdSpeedIndicatorHideDelay
                                    .formatted(.number.precision(.fractionLength(0...1)))
                                showingHideDelayEditor = true
                            } label: {
                                LabeledContent("Hide after") {
                                    Text(verbatim: Measurement(value: holdSpeedIndicatorHideDelay, unit: UnitDuration.seconds)
                                        .formatted(.measurement(
                                            width: .abbreviated,
                                            numberFormatStyle: .number.precision(.fractionLength(0...1))
                                        )))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                            .settingsSearchRow("Hide after")
                        }
                    }
                }
                Toggle("Autoplay next video", isOn: Bindable(model).autoplayNext)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Autoplay next video")
                Toggle("Allow audio from other apps", isOn: Bindable(model).allowAudioMixing)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Allow audio from other apps")
                Toggle("Resume after interruptions", isOn: Bindable(model).resumeAfterAudioInterruption)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Resume after interruptions")
            } header: {
                Text("Video & audio")
            } footer: {
                Text("Quality is a maximum for adaptive streams, not a guaranteed resolution. The cellular limit applies to HLS on expensive networks; fixed-quality and downloaded files keep their encoded resolution. Allowing other audio may leave another app in control of Lock Screen playback.")
            }

        }
        .scrollToSearchedSetting()
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Hold speed", isPresented: $showingHoldSpeedEditor) {
            TextField("Speed", text: $holdSpeedText)
                .keyboardType(.decimalPad)
            Button("Set Speed") {
                if let rate = PlaybackSpeedPresets.parse(holdSpeedText) {
                    model.holdSpeedRate = rate
                }
            }
            .disabled(PlaybackSpeedPresets.parse(holdSpeedText) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter 0.25× to 5×, with up to two decimal places.")
        }
        .alert("Hide after", isPresented: $showingHideDelayEditor) {
            TextField("Seconds", text: $hideDelayText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let delay = parsedHideDelay { holdSpeedIndicatorHideDelay = delay }
            }
            .disabled(parsedHideDelay == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter 0.5 to 10 seconds.")
        }
    }

    /// Accepts the device's decimal separator; one decimal place is kept.
    private var parsedHideDelay: Double? {
        let text = hideDelayText.trimmingCharacters(in: .whitespaces)
        guard let value = try? Double(text, format: .number),
              HoldSpeedIndicatorStyle.hideDelayRange.contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    private var defaultPlaybackRates: [Double] {
        PlaybackSpeedPresets.availableRates(
            savedRaw: savedPlaybackSpeedsRaw,
            legacyCustomRaw: legacyCustomPlaybackSpeedsRaw
        )
    }
}
