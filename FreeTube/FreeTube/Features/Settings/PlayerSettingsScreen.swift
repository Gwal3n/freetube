import SwiftUI

@available(iOS 17.0, *)
struct PlayerSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel
    @AppStorage("cacheRecentVideoContent") private var cacheRecentVideoContent = true
    @AppStorage("horizontalSwipeToSeekEnabled") private var horizontalSwipeToSeekEnabled = true
    @AppStorage("showPlayerSaveButton") private var showPlayerSaveButton = true
    @AppStorage("showPlayerShareButton") private var showPlayerShareButton = true
    @AppStorage("showPlayerDownloadButton") private var showPlayerDownloadButton = true
    @AppStorage("customDoubleTapSeekSeconds") private var customDoubleTapSeekSeconds = 20
    @AppStorage("watchProgressColorMode") private var watchProgressColorMode = WatchIndicatorStyle.ColorMode.red.rawValue
    @AppStorage("watchProgressCustomHex") private var watchProgressCustomHex = "#FF0000"
    @AppStorage("playerScrubberColorMode") private var playerScrubberColorMode = PlayerScrubberColorMode.standard.rawValue
    @AppStorage("playerScrubberCustomHex") private var playerScrubberCustomHex = "#FF0000"
    @AppStorage("finishedVideoIndicator") private var finishedVideoIndicator = WatchIndicatorStyle.FinishedMode.none.rawValue
    @AppStorage("transportButtonMode") private var transportButtonMode = "videos"
    @AppStorage("transportSeekSeconds") private var transportSeekSeconds = 10
    @AppStorage("upNextRowSize") private var upNextRowSize = UpNextRowSize.compact.rawValue
    @State private var showingCustomSeekEditor = false
    @State private var customSeekSecondsText = ""

    private let presetSeekIntervals = [5, 10, 15, 30]

    var body: some View {
        Form {
            Section {
                Toggle("Swipe horizontally to seek", isOn: $horizontalSwipeToSeekEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Swipe horizontally to seek")
                Picker("Double-tap seek", selection: seekIntervalSelection) {
                    Text("Off").tag(0)
                    ForEach(presetSeekIntervals, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                    Text("Custom (\(customDoubleTapSeekSeconds) seconds)").tag(-1)
                }
                .settingsSearchRow("Double-tap seek")
                if isCustomSeekIntervalSelected {
                    Button {
                        editCustomSeekInterval()
                    } label: {
                        LabeledContent("Custom interval") {
                            Text("\(model.doubleTapSeekSeconds) seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Custom interval")
                }
                Picker("Seek preview", selection: Bindable(model).seekPreviewStyle) {
                    Text("Compact").tag(SeekPreviewStyle.compact)
                    Text("Large").tag(SeekPreviewStyle.large)
                    Text("Off").tag(SeekPreviewStyle.off)
                }
                .settingsSearchRow("Seek preview")
                Picker("Vertical swipe in fullscreen", selection: Bindable(model).playerVerticalSwipeAction) {
                    Text("Exit fullscreen").tag(PlayerVerticalSwipeAction.fullscreen)
                    Text("Adjust brightness and volume").tag(PlayerVerticalSwipeAction.adjustPlayback)
                    Text("Off").tag(PlayerVerticalSwipeAction.off)
                }
                .settingsSearchRow("Vertical swipe in fullscreen")
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Picker("Left side", selection: Bindable(model).leftFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .settingsSearchRow("Left side")
                    Picker("Right side", selection: Bindable(model).rightFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .settingsSearchRow("Right side")
                }
            } header: {
                Text("Gestures")
            } footer: {
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Text("Volume swipes adjust FreeTube playback, not the iPhone's system volume.")
                }
            }

            Section {
                Toggle("Save", isOn: $showPlayerSaveButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Save button")
                Toggle("Share", isOn: $showPlayerShareButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Share button")
                Toggle("Download", isOn: $showPlayerDownloadButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Download button")
            } header: {
                Text("Buttons below video")
            } footer: {
                Text("These switches hide shortcuts below the video without removing saved items or downloads.")
            }

            Section("Playback timeline") {
                Picker("Scrubber color", selection: $playerScrubberColorMode) {
                    Text("Default red").tag(PlayerScrubberColorMode.standard.rawValue)
                    Text("Custom").tag(PlayerScrubberColorMode.custom.rawValue)
                }
                .settingsSearchRow("Scrubber color")
                if playerScrubberColorMode == PlayerScrubberColorMode.custom.rawValue {
                    ColorPicker("Custom scrubber color", selection: Binding(
                        get: { WatchIndicatorStyle.color(hex: playerScrubberCustomHex) ?? .red },
                        set: { playerScrubberCustomHex = WatchIndicatorStyle.hex(color: $0) }
                    ), supportsOpacity: false)
                    .settingsSearchRow("Custom scrubber color")
                }
            }

            Section {
                Toggle("Remember floating player placement", isOn: Bindable(model).rememberFloatingPlayerPlacement)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Remember floating player placement")
                Toggle("Show watch progress bars", isOn: Bindable(model).showHistoryProgressBars)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show watch progress bars")
                if model.showHistoryProgressBars {
                    Picker("Watch progress color", selection: $watchProgressColorMode) {
                        Text("Red").tag(WatchIndicatorStyle.ColorMode.red.rawValue)
                        Text("Accent color").tag(WatchIndicatorStyle.ColorMode.accent.rawValue)
                        Text("Custom").tag(WatchIndicatorStyle.ColorMode.custom.rawValue)
                    }
                    .settingsSearchRow("Watch progress color")
                    if watchProgressColorMode == WatchIndicatorStyle.ColorMode.custom.rawValue {
                        ColorPicker("Custom progress color", selection: Binding(
                            get: { WatchIndicatorStyle.color(hex: watchProgressCustomHex) ?? .red },
                            set: { watchProgressCustomHex = WatchIndicatorStyle.hex(color: $0) }
                        ), supportsOpacity: false)
                    }
                    Picker("Fully watched videos", selection: $finishedVideoIndicator) {
                        Text("Full progress bar").tag(WatchIndicatorStyle.FinishedMode.fullBar.rawValue)
                        Text("Checkmark").tag(WatchIndicatorStyle.FinishedMode.checkmark.rawValue)
                        Text("No indicator").tag(WatchIndicatorStyle.FinishedMode.none.rawValue)
                    }
                    .settingsSearchRow("Fully watched videos")
                }
                Picker("Transport buttons", selection: $transportButtonMode) {
                    Text("Previous and next video").tag("videos")
                    Text("Seek backward and forward").tag("seek")
                }
                .settingsSearchRow("Transport buttons")
                if transportButtonMode == "seek" {
                    Stepper(value: $transportSeekSeconds, in: 1...120) {
                        LabeledContent("Seek button interval") {
                            Text("\(transportSeekSeconds) seconds")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Seek button interval")
                }
                Toggle("Show description", isOn: Bindable(model).showDescription)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show description")
                Toggle("Show comments", isOn: Bindable(model).showComments)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show comments")
                if model.showComments {
                    Toggle("Show commenter photos", isOn: Bindable(model).showCommentAuthorPhotos)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Show commenter photos")
                    Toggle("Open commenter channels", isOn: Bindable(model).openCommentAuthorChannels)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Open commenter channels")
                    Toggle("Show featured comment preview", isOn: Bindable(model).showFeaturedCommentPreview)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Show featured comment preview")
                    if model.showFeaturedCommentPreview {
                        Toggle("Only near playback time", isOn: Bindable(model).featuredCommentsNearPlaybackOnly)
                            .tint(settingsToggleTint)
                            .settingsSearchRow("Only near playback time")
                    }
                }
                Toggle("Show Up Next", isOn: Bindable(model).showUpNext)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Up Next")
                if model.showUpNext {
                    Picker("Up Next video size", selection: $upNextRowSize) {
                        ForEach(UpNextRowSize.allCases) { size in
                            Text(size.title).tag(size.rawValue)
                        }
                    }
                    .settingsSearchRow("Up Next video size")
                    Stepper(value: Bindable(model).upNextInitialCount, in: 3...15) {
                        LabeledContent("Initial Up Next videos") {
                            Text("\(model.upNextInitialCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Initial Up Next videos")
                }
                NavigationLink {
                    PlayerSectionsSettingsScreen()
                } label: {
                    Label("Rearrange sections", systemImage: "line.3.horizontal")
                }
                .settingsSearchRow("Rearrange sections")
                Toggle("Prefetch details and comments", isOn: Bindable(model).prefetchVideoDetails)
                    .tint(settingsToggleTint)
                    .disabled(!cacheRecentVideoContent)
                    .settingsSearchRow("Prefetch details and comments")
                NavigationLink {
                    PlayerControlsSettingsScreen(model: model)
                } label: {
                    Label("Customize controls", systemImage: "slider.horizontal.3")
                }
                .settingsSearchRow("Customize controls")
            } header: {
                Text("Content & controls")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if isCustomSeekIntervalSelected {
                customDoubleTapSeekSeconds = model.doubleTapSeekSeconds
            }
        }
        .alert("Custom seek interval", isPresented: $showingCustomSeekEditor) {
            TextField("Seconds", text: $customSeekSecondsText)
                .keyboardType(.numberPad)
            Button("Set Interval") {
                guard let seconds = parsedCustomSeekInterval else { return }
                customDoubleTapSeekSeconds = seconds
                model.doubleTapSeekSeconds = seconds
            }
            .disabled(parsedCustomSeekInterval == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter 1 to 120 seconds.")
        }
    }

    private var isCustomSeekIntervalSelected: Bool {
        model.doubleTapSeekSeconds != 0 && !presetSeekIntervals.contains(model.doubleTapSeekSeconds)
    }

    private var seekIntervalSelection: Binding<Int> {
        Binding(
            get: { isCustomSeekIntervalSelected ? -1 : model.doubleTapSeekSeconds },
            set: { selection in
                if selection == -1 {
                    editCustomSeekInterval()
                } else {
                    model.doubleTapSeekSeconds = selection
                }
            }
        )
    }

    private var parsedCustomSeekInterval: Int? {
        guard let seconds = Int(customSeekSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...120).contains(seconds) else { return nil }
        return seconds
    }

    private func editCustomSeekInterval() {
        customSeekSecondsText = String(isCustomSeekIntervalSelected ? model.doubleTapSeekSeconds : customDoubleTapSeekSeconds)
        showingCustomSeekEditor = true
    }
}
