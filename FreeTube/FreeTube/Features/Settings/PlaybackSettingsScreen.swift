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
                Picker("Cellular streaming limit", selection: Bindable(model).cellularPlaybackQuality) {
                    Text("No extra limit").tag(VideoQuality.auto)
                    ForEach(VideoQuality.allCases.filter { $0 != .auto && $0 != .audioOnly }) { quality in
                        Text("Up to \(quality.displayName)").tag(quality)
                    }
                }
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
                .onChange(of: model.defaultPlaybackRate) { _, rate in
                    player.setPlaybackRate(rate)
                }
                .onChange(of: savedPlaybackSpeedsRaw) { _, _ in
                    if !defaultPlaybackRates.contains(model.defaultPlaybackRate) {
                        model.defaultPlaybackRate = 1
                    }
                }
                Toggle("Hold for speed", isOn: Bindable(model).holdForSpeedEnabled)
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
                Toggle("Autoplay next video", isOn: Bindable(model).autoplayNext)
                Toggle("Allow audio from other apps", isOn: Bindable(model).allowAudioMixing)
                Toggle("Resume after interruptions", isOn: Bindable(model).resumeAfterAudioInterruption)
            } header: {
                Text("Playback")
            } footer: {
                Text("Quality is a maximum for adaptive streams, not a guaranteed resolution. The cellular limit applies to HLS on expensive networks; fixed-quality and downloaded files keep their encoded resolution. Allowing other audio may leave another app in control of Lock Screen playback.")
            }

            Section {
                Picker("Double-tap seek", selection: Bindable(model).doubleTapSeekSeconds) {
                    ForEach([5, 10, 15, 30], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                Picker("Seek preview", selection: Bindable(model).seekPreviewStyle) {
                    Text("Compact").tag(SeekPreviewStyle.compact)
                    Text("Large").tag(SeekPreviewStyle.large)
                    Text("Off").tag(SeekPreviewStyle.off)
                }
                Picker("Vertical swipe in fullscreen", selection: Bindable(model).playerVerticalSwipeAction) {
                    Text("Exit fullscreen").tag(PlayerVerticalSwipeAction.fullscreen)
                    Text("Adjust brightness and volume").tag(PlayerVerticalSwipeAction.adjustPlayback)
                    Text("Off").tag(PlayerVerticalSwipeAction.off)
                }
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Picker("Left side", selection: Bindable(model).leftFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    Picker("Right side", selection: Bindable(model).rightFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                }
                Toggle("Remember floating player placement", isOn: Bindable(model).rememberFloatingPlayerPlacement)
                Toggle("Show watch progress bars", isOn: Bindable(model).showHistoryProgressBars)
                Toggle("Show description", isOn: Bindable(model).showDescription)
                Toggle("Show comments", isOn: Bindable(model).showComments)
                if model.showComments {
                    Toggle("Show featured comment preview", isOn: Bindable(model).showFeaturedCommentPreview)
                }
                Toggle("Show Up Next", isOn: Bindable(model).showUpNext)
                if model.showUpNext {
                    Stepper(value: Bindable(model).upNextInitialCount, in: 3...15) {
                        LabeledContent("Initial Up Next videos") {
                            Text("\(model.upNextInitialCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("Prefetch details and comments", isOn: Bindable(model).prefetchVideoDetails)
                NavigationLink {
                    PlayerControlsSettingsScreen(model: model)
                } label: {
                    Label("Customize controls", systemImage: "slider.horizontal.3")
                }
                .tint(.primary)
            } header: {
                Text("Player")
            } footer: {
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Text("Volume swipes adjust FreeTube playback, not the iPhone's system volume.")
                }
            }

            Section("Captions") {
                Toggle("Dark caption background", isOn: Bindable(model).captionBackgroundEnabled)
                Toggle("Use source formatting", isOn: Bindable(model).formattedCaptions)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Caption text size")
                        Spacer()
                        Text(verbatim: "\(Int((model.captionTextScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Bindable(model).captionTextScale, in: 0.8...1.5, step: 0.1)
                        .accessibilityLabel("Caption text size")
                }
            }
        }
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
