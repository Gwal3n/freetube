import SwiftUI

@available(iOS 17.0, *)
struct PlaybackSettingsScreen: View {
    let model: SettingsViewModel
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("playbackSpeedChoices") private var savedPlaybackSpeedsRaw = ""
    @AppStorage("customPlaybackSpeeds") private var legacyCustomPlaybackSpeedsRaw = ""
    @State private var showingHoldSpeedEditor = false
    @State private var holdSpeedText = ""

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
                .tint(.primary)
                .settingsSearchRow("Playback speeds")
                .onChange(of: model.defaultPlaybackRate) { _, rate in
                    player.setPlaybackRate(rate)
                }
                .onChange(of: savedPlaybackSpeedsRaw) { _, _ in
                    if !defaultPlaybackRates.contains(model.defaultPlaybackRate) {
                        model.defaultPlaybackRate = 1
                    }
                }
                Toggle("Hold for speed", isOn: Bindable(model).holdForSpeedEnabled)
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
                .tint(.primary)
                .disabled(!model.holdForSpeedEnabled)
                .settingsSearchRow("Hold speed")
                Toggle("Autoplay next video", isOn: Bindable(model).autoplayNext)
                    .settingsSearchRow("Autoplay next video")
                Toggle("Allow audio from other apps", isOn: Bindable(model).allowAudioMixing)
                    .settingsSearchRow("Allow audio from other apps")
                Toggle("Resume after interruptions", isOn: Bindable(model).resumeAfterAudioInterruption)
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
    }

    private var defaultPlaybackRates: [Double] {
        PlaybackSpeedPresets.availableRates(
            savedRaw: savedPlaybackSpeedsRaw,
            legacyCustomRaw: legacyCustomPlaybackSpeedsRaw
        )
    }
}
