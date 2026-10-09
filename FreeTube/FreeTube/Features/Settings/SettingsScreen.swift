import SwiftUI

@available(iOS 17.0, *)
struct SettingsScreen: View {
    let onClose: () -> Void
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @State private var model = SettingsViewModel()
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    /// Observed so the "Save logs to file" section re-renders when the writer opens / closes
    /// the current log file.
    @State private var logWriter = LogFileWriter.shared

    /// Wraps a single URL for the Share sheet. Optional because the sheet only presents when
    /// the user taps "Share latest log" AND there's a file to share. `nil` → sheet not shown.
    @State private var shareLogURL: URL?

    /// "Are you sure?" confirmation for the destructive Clear-all-logs button.
    @State private var showingClearLogsConfirmation = false
    @State private var showingClearHistoryConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Preferred quality", selection: Bindable(model).preferredQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    Picker("Default playback speed", selection: Bindable(model).playbackRate) {
                        ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                            Text(verbatim: rate == 1 ? "Normal" : "\(rate.formatted())×").tag(rate)
                        }
                    }
                    .onChange(of: model.playbackRate) { _, rate in
                        player.setPlaybackRate(rate)
                    }
                    Toggle("Autoplay next video", isOn: Bindable(model).autoplayNext)
                    Toggle("Swipe vertically for fullscreen", isOn: Bindable(model).verticalSwipeFullscreen)
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
                    Toggle("Allow audio from other apps", isOn: Bindable(model).allowAudioMixing)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Quality is a maximum for adaptive streams, not a guaranteed resolution. Prefetching loads details and the first comments page after playback starts. Allowing other audio may leave another app in control of Lock Screen playback.")
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

                Section {
                    Toggle("Show search suggestions", isOn: Bindable(model).showSearchSuggestions)
                    Toggle("Save recent searches", isOn: Bindable(model).saveSearchHistory)
                } header: {
                    Text("Search")
                } footer: {
                    Text("Turning off recent searches stops saving new queries. Existing searches remain until cleared from Search.")
                }

                Section("Privacy") {
                    NavigationLink {
                        IncognitoSettingsScreen()
                    } label: {
                        HStack {
                            navigationLabel("Incognito", systemImage: "eye.slash")
                            Spacer()
                            if incognitoEnabled {
                                Text("On")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.white)
                    NavigationLink {
                        VideoBlockingSettingsScreen()
                    } label: {
                        navigationLabel("Blocked content", systemImage: "hand.raised")
                    }
                    .tint(.white)
                }

                Section {
                    Toggle("Show subscription feed tab", isOn: Bindable(model).showSubscriptionFeedTab)
                    Toggle("Large video thumbnails", isOn: Bindable(model).largeSubscriptionFeedThumbnails)
                    Toggle("Mark new uploads", isOn: Bindable(model).showNewSubscriptionUploads)
                    Toggle("Refresh feed automatically", isOn: Bindable(model).automaticFeedRefreshEnabled)
                    if model.automaticFeedRefreshEnabled {
                        Picker("Refresh interval", selection: Bindable(model).automaticFeedRefreshInterval) {
                            ForEach(FeedRefreshInterval.allCases) { interval in
                                switch interval {
                                case .hourly: Text("Every hour").tag(interval)
                                case .everySixHours: Text("Every 6 hours").tag(interval)
                                case .everyTwelveHours: Text("Every 12 hours").tag(interval)
                                case .daily: Text("Every day").tag(interval)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Feed")
                } footer: {
                    Text("Hiding Feed does not remove your subscriptions. Automatic refresh runs only while the Feed tab is selected and the app is active.")
                }

                Section("Channels") {
                    NavigationLink {
                        SubscriptionGroupsScreen(isEmbedded: true)
                    } label: {
                        navigationLabel("Manage subscription groups", systemImage: "square.stack.3d.up")
                    }
                    .tint(.white)
                    NavigationLink {
                        ChannelTabsSettingsScreen()
                    } label: {
                        navigationLabel("Channel tabs", systemImage: "rectangle.stack")
                    }
                    .tint(.white)
                }

                Section {
                    Picker("Text font", selection: Bindable(model).appFontPreset) {
                        ForEach(AppFontPreset.allCases) { preset in
                            preset.label
                                .font(preset.font(.body))
                                .tag(preset)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    NavigationLink {
                        CommunityEnhancementsSettingsScreen(model: model)
                            .onAppear { log.info("Settings community enhancements destination appeared") }
                    } label: {
                        navigationLabel("SponsorBlock and DeArrow", systemImage: "sparkles")
                    }
                    .tint(.white)
                } header: {
                    Text("Community enhancements")
                }

                Section("Player controls") {
                    NavigationLink {
                        PlayerControlsSettingsScreen(model: model)
                            .onAppear { log.info("Settings controls destination appeared") }
                    } label: {
                        navigationLabel("Customize controls", systemImage: "slider.horizontal.3")
                    }
                    .tint(.white)
                }

                Section {
                    NavigationLink {
                        ImportDataScreen()
                            .onAppear { log.info("Settings import destination appeared") }
                    } label: {
                        navigationLabel("Import & Export", systemImage: "square.and.arrow.down")
                    }
                    .tint(.white)
                    Toggle("Save watch history", isOn: Bindable(model).saveWatchHistory)
                    Toggle("Continue Watching in Library", isOn: Bindable(model).showContinueWatchingMenu)
                    Toggle("Library video shelf", isOn: Bindable(model).showLibraryShelf)
                        .disabled(!model.saveWatchHistory)
                    if model.showLibraryShelf && model.saveWatchHistory {
                        Picker("Shelf content", selection: Bindable(model).libraryShelfContent) {
                            ForEach(LibraryShelfContent.allCases) { content in
                                Text(content.settingsTitle).tag(content)
                            }
                        }
                        Stepper(value: Bindable(model).recentLibraryVideoCount, in: 3...12) {
                            LabeledContent("Shelf videos") {
                                Text("\(model.recentLibraryVideoCount)")
                                    .monospacedDigit()
                            }
                        }
                    }
                    Picker("Keep watch history", selection: Bindable(model).historyRetentionPolicy) {
                        ForEach(HistoryRetentionPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .disabled(!model.saveWatchHistory)
                    Button(role: .destructive) {
                        showingClearHistoryConfirmation = true
                    } label: {
                        Label("Clear Watch History", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Turning this off stops recording history and playback positions. Existing history stays on this device until you clear it.")
                }

                Section {
                    Toggle("Allow cellular data", isOn: Bindable(model).allowCellularDownloads)
                    Picker("Parallel fragments", selection: Bindable(model).concurrentFragments) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { value in
                            Text(value == 1 ? "1 (sequential)" : "\(value)").tag(value)
                        }
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    DownloadsSettingsFooter()
                }

                Section {
                    Toggle("Save logs to file", isOn: Bindable(model).logToFile)
                    if model.logToFile, let url = logWriter.currentLogFileURL {
                        LabeledContent("Current log") {
                            Text(url.lastPathComponent)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Button {
                        // Prefer the active file; fall back to the latest historical one
                        // so the Share button still works right after the toggle is flipped
                        // off (writer closes the file, currentLogFileURL goes nil, but the
                        // file is still on disk and shareable).
                        log.info("Settings Share latest log requested")
                        shareLogURL = logWriter.currentLogFileURL ?? LogFileWriter.allLogFiles().first
                    } label: {
                        Label("Share latest log…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(LogFileWriter.allLogFiles().isEmpty)
                    if MacIntegration.isRunningOnMac {
                        Button {
                            MacIntegration.revealInFinder(LogFileWriter.logsDirectory())
                        } label: {
                            Label("Show log folder", systemImage: "folder")
                        }
                    }
                    Button(role: .destructive) {
                        showingClearLogsConfirmation = true
                    } label: {
                        Label("Clear all logs", systemImage: "trash")
                    }
                    .disabled(LogFileWriter.allLogFiles().isEmpty)
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Saving logs creates a new file at launch for troubleshooting. Logs include app and device details, but omit sensitive URL queries.")
                }

                Section {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .monospacedDigit()
                    }
                    LabeledContent("Build") {
                        Text(appBuild)
                            .monospacedDigit()
                    }
                    LabeledContent("Revision") {
                        Text(appRevision)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    Text("An account-free YouTube client for personal use. Playback and downloads may break when YouTube changes its internal APIs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                } footer: {
                    Text("[freetube.io](https://freetube.io)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        log.info("Settings Done requested")
                        onClose()
                    }
                }
            }
            // System Share sheet for the log file. `ShareLink` would be cleaner, but
            // file:// URLs inside SwiftUI's `ShareLink` sometimes serialize as plain text
            // — UIActivityViewController via the existing `ActivityShareSheet` is the
            // reliable path for picking "Save to Files", AirDrop, Mail, etc.
            .sheet(isPresented: Binding(
                get: { shareLogURL != nil },
                set: { if !$0 { shareLogURL = nil } }
            )) {
                if let url = shareLogURL {
                    ActivityShareSheet(activityItems: [url])
                }
            }
            .confirmationDialog(
                "Delete all log files?",
                isPresented: $showingClearLogsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    model.clearLogFiles()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every saved diagnostic log. If \"Save logs to file\" is on, a fresh log file will be opened for new entries.")
            }
            .confirmationDialog(
                "Clear local watch history?",
                isPresented: $showingClearHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    model.clearLocalHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes watch history stored by FreeTube on this device.")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var appRevision: String {
        guard let revision = Bundle.main.infoDictionary?["FreeTubeCommit"] as? String,
              !revision.isEmpty else { return "local" }
        return revision
    }

    private func navigationLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
        .foregroundStyle(.primary)
    }
}
