import SwiftUI

@available(iOS 17.0, *)
struct PlayerSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel
    @AppStorage("horizontalSwipeToSeekEnabled") private var horizontalSwipeToSeekEnabled = true
    @AppStorage("centerTapPlayPauseEnabled") private var centerTapPlayPauseEnabled = false
    @AppStorage("showPlayerSaveButton") private var showPlayerSaveButton = true
    @AppStorage("showPlayerShareButton") private var showPlayerShareButton = true
    @AppStorage("showPlayerDownloadButton") private var showPlayerDownloadButton = true
    @AppStorage("customDoubleTapSeekSeconds") private var customDoubleTapSeekSeconds = 20
    @AppStorage("playerScrubberColorMode") private var playerScrubberColorMode = PlayerScrubberColorMode.standard.rawValue
    @AppStorage("playerScrubberCustomHex") private var playerScrubberCustomHex = "#FF0000"
    @AppStorage("transportButtonMode") private var transportButtonMode = "videos"
    @AppStorage("transportSeekSeconds") private var transportSeekSeconds = 10
    @AppStorage("upNextRowSize") private var upNextRowSize = UpNextRowSize.compact.rawValue
    @AppStorage("showUpNextChannelAvatars") private var showUpNextChannelAvatars = false
    @AppStorage("openUpNextChannelsOnTap") private var openUpNextChannelsOnTap = false
    @AppStorage("autoLoadMoreComments") private var autoLoadMoreComments = true
    @AppStorage("pinCommentsHeading") private var pinCommentsHeading = false
    @AppStorage("pinUpNextHeading") private var pinUpNextHeading = false
    @AppStorage("pinQueueHeading") private var pinQueueHeading = false
    @State private var showingCustomSeekEditor = false
    @State private var customSeekSecondsText = ""

    private let presetSeekIntervals = [5, 10, 15, 30]

    var body: some View {
        Form {
            Section {
                Toggle("Tap video to play or pause", isOn: $centerTapPlayPauseEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Tap video to play or pause")
                Toggle("Swipe to seek", isOn: $horizontalSwipeToSeekEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Swipe to seek")
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
                    Text("Brightness and volume").tag(PlayerVerticalSwipeAction.adjustPlayback)
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
            }

            Section {
                Picker("Transport buttons", selection: $transportButtonMode) {
                    Text("Previous / next video").tag("videos")
                    Text("Seek backward / forward").tag("seek")
                    Text("Off").tag("off")
                }
                .settingsSearchRow("Transport buttons")
                if transportButtonMode == "seek" {
                    Stepper(value: $transportSeekSeconds, in: 1...120) {
                        LabeledContent("Seek amount") {
                            Text("\(transportSeekSeconds) seconds")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Seek amount")
                }
                NavigationLink {
                    PlayerControlsSettingsScreen(model: model)
                } label: {
                    Label("Top controls layout", systemImage: "slider.horizontal.3")
                }
                .settingsSearchRow("Top controls layout")
                Toggle("Show Save button", isOn: $showPlayerSaveButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Save button")
                Toggle("Show Share button", isOn: $showPlayerShareButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Share button")
                Toggle("Show Download button", isOn: $showPlayerDownloadButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Download button")
            } header: {
                Text("Controls")
            }

            Section {
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
            } header: {
                Text("Timeline")
            }

            Section {
                Toggle("Remember mini player position", isOn: Bindable(model).rememberFloatingPlayerPlacement)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Remember mini player position")
            } header: {
                Text("Mini player")
            }

            Section {
                Toggle("Show description", isOn: Bindable(model).showDescription)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show description")
                if model.showDescription {
                    Toggle("Collapsed description preview", isOn: Bindable(model).showCollapsedDescriptionPreview)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Collapsed description preview")
                }
                Toggle("Show comments", isOn: Bindable(model).showComments)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show comments")
                if model.showComments {
                    Toggle("Pin Comments heading", isOn: $pinCommentsHeading)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Pin Comments heading")
                    Toggle("Load more as you scroll", isOn: $autoLoadMoreComments)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Load more as you scroll")
                    Toggle("Show commenter photos", isOn: Bindable(model).showCommentAuthorPhotos)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Show commenter photos")
                    Toggle("Tap commenter to open channel", isOn: Bindable(model).openCommentAuthorChannels)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Tap commenter to open channel")
                    Picker("Featured comment preview", selection: featuredCommentSelection) {
                        Text("Off").tag("off")
                        Text("Near playback time").tag("timed")
                        Text("Always").tag("always")
                    }
                    .settingsSearchRow("Featured comment preview")
                }
                Toggle("Show Up Next", isOn: Bindable(model).showUpNext)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Up Next")
                if model.showUpNext {
                    Toggle("Pin Up Next heading", isOn: $pinUpNextHeading)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Pin Up Next heading")
                    Toggle("Show channel avatars", isOn: $showUpNextChannelAvatars)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Show channel avatars")
                    Toggle("Tap channel to open", isOn: $openUpNextChannelsOnTap)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Tap channel to open")
                    Picker("Thumbnail size", selection: $upNextRowSize) {
                        ForEach(UpNextRowSize.allCases) { size in
                            Text(size.title).tag(size.rawValue)
                        }
                    }
                    .settingsSearchRow("Thumbnail size")
                    Stepper(value: Bindable(model).upNextInitialCount, in: 3...15) {
                        LabeledContent("Videos shown at first") {
                            Text("\(model.upNextInitialCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Videos shown at first")
                }
                Toggle("Pin Queue heading", isOn: $pinQueueHeading)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Pin Queue heading")
                NavigationLink {
                    PlayerSectionsSettingsScreen()
                } label: {
                    Label("Reorder sections", systemImage: "line.3.horizontal")
                }
                .settingsSearchRow("Reorder sections")
            } header: {
                Text("Details panel")
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

    private var featuredCommentSelection: Binding<String> {
        Binding(
            get: {
                guard model.showFeaturedCommentPreview else { return "off" }
                return model.featuredCommentsNearPlaybackOnly ? "timed" : "always"
            },
            set: { selection in
                model.featuredCommentsNearPlaybackOnly = selection == "timed"
                model.showFeaturedCommentPreview = selection != "off"
            }
        )
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
