import SwiftUI

@available(iOS 17.0, *)
struct SettingsScreen: View {
    private enum Destination: String, Hashable {
        case sponsorBlock, playerControls, importData, probe
    }

    @State private var path = NavigationPath()
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack(path: navigationPathBinding) {
            Form {
                Section {
                    Picker("Preferred quality", selection: Bindable(model).preferredQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    Toggle("Autoplay next video", isOn: Bindable(model).autoplayNext)
                    Toggle("Swipe vertically for fullscreen", isOn: Bindable(model).verticalSwipeFullscreen)
                    Toggle("Show watch progress bars", isOn: Bindable(model).showHistoryProgressBars)
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
                    Text("The featured preview shows YouTube’s own comment excerpt while Comments is collapsed. Prefetching starts only after playback is ready and loads the description plus the first comments page when comments are enabled. Further comments and replies remain on demand.\n\nAllowing audio from other apps lets FreeTube play alongside music, podcasts, and other active audio. The app that owns lock-screen controls can depend on which one started first.")
                }

                Section("Search") {
                    Toggle("Restricted search mode", isOn: Bindable(model).restrictedSearchMode)
                }

                Section {
                    Toggle("Show subscription feed tab", isOn: Bindable(model).showSubscriptionFeedTab)
                    Toggle("Large video thumbnails", isOn: Bindable(model).largeSubscriptionFeedThumbnails)
                } header: {
                    Text("Feed")
                } footer: {
                    Text("Hiding the tab keeps your local subscriptions and cached feed on this device. Large thumbnails use spacious 16:9 cards while preserving the same playback and queue actions.")
                }

                Section {
                    Toggle("OLED player background", isOn: Bindable(model).oledPlayerBackground)
                    Toggle("OLED mini-player", isOn: Bindable(model).oledMiniPlayer)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The expanded-player option uses true black for video information, Up Next, and comments. The mini-player option replaces its default Liquid Glass with true black.")
                }

                Section {
                    Button {
                        open(.sponsorBlock)
                    } label: {
                        HStack {
                            Text("Categories and behavior")
                            Spacer()
                            Text(model.sponsorBlockEnabled ? "On" : "Off")
                                .foregroundStyle(.secondary)
                            disclosureIndicator
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .tint(.white)
                    .navigationDiagnostics("Settings row SponsorBlock")
                } header: {
                    Text("SponsorBlock")
                } footer: {
                    Text("Show or skip community-identified video segments without delaying playback.")
                }

                Section {
                    Toggle("Replace video titles", isOn: Bindable(model).deArrowTitles)
                    Toggle("Replace video thumbnails", isOn: Bindable(model).deArrowThumbnails)
                    if model.deArrowThumbnails {
                        Toggle("Random thumbnail when no submission exists", isOn: Bindable(model).deArrowRandomThumbnails)
                    }
                } header: {
                    Text(verbatim: "DeArrow")
                } footer: {
                    Text("Use community titles and video frames to reduce clickbait. If no thumbnail has been submitted, a stable random frame can be requested instead. Tap the small switch on a video to see its original title and thumbnail. Originals stay saved on this device. Enabling this sends anonymous requests to DeArrow; thumbnail requests include the video ID. If the service is unavailable, the originals remain visible.")
                }

                Section("Player controls") {
                    Button {
                        open(.playerControls)
                    } label: {
                        navigationLabel("Customize controls", systemImage: "slider.horizontal.3")
                    }
                    .tint(.white)
                    .navigationDiagnostics("Settings row player controls")
                }

                Section("Data") {
                    Button {
                        open(.importData)
                    } label: {
                        navigationLabel("Import Data", systemImage: "square.and.arrow.down")
                    }
                    .tint(.white)
                    .navigationDiagnostics("Settings row import data")
                    Picker("Keep watch history", selection: Bindable(model).historyRetentionPolicy) {
                        ForEach(HistoryRetentionPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    Button(role: .destructive) {
                        showingClearHistoryConfirmation = true
                    } label: {
                        Label("Clear Watch History", systemImage: "trash")
                    }
                }

                Section {
                    Toggle("Allow cellular data", isOn: Bindable(model).allowCellularDownloads)
                    Picker("Cache limit", selection: Bindable(model).downloadCacheLimit) {
                        ForEach(DownloadCacheLimit.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
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
                    LabeledContent("Version") {
                        Text(model.ytDlpVersion.isEmpty ? "Not yet loaded" : model.ytDlpVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    LabeledContent("Last updated") {
                        Text(model.ytDlpLastUpdatedDisplay ?? "Never")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.updateYtDlpNow()
                    } label: {
                        HStack {
                            Label("Update now", systemImage: "arrow.down.circle")
                            if model.isUpdatingYtDlp {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isUpdatingYtDlp)

                    if let status = model.ytDlpUpdateStatus {
                        switch status {
                        case .success(let version):
                            Label("Updated to \(version)", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                                .font(.footnote)
                        case .noChange(let version):
                            Label("Already at latest (\(version))", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        case .failure(let message):
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text(verbatim: "yt-dlp")
                } footer: {
                    Text("yt-dlp is the engine that resolves YouTube stream URLs. FreeTube auto-refreshes it every 7 days from the official GitHub release. Tap Update now if a video stops playing — newer versions often fix breakage caused by YouTube's API changes.")
                }

                Section {
                    Button("Test Settings navigation") {
                        open(.probe)
                    }
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
                    Text("When enabled, every app launch creates a private diagnostic log that can be exported with Share. Each file starts with the app version, build, iOS version, and device model, followed by timestamped entries from FreeTube's subsystem. Sensitive URL query strings are excluded.")
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
                    Text("FreeTube is a personal, account-free YouTube client. It uses anonymous YouTubeKit requests without a Google API key, plus yt-dlp for downloads. YouTube can change its internal API at any time — please be patient when things break.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                } footer: {
                    Text("[freetube.io](https://freetube.io)")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .sponsorBlock:
                    SponsorBlockSettingsScreen(model: model)
                        .navigationDiagnostics("Settings destination SponsorBlock")
                case .playerControls:
                    PlayerControlsSettingsScreen(model: model)
                        .navigationDiagnostics("Settings destination player controls")
                case .importData:
                    ImportDataScreen()
                        .navigationDiagnostics("Settings destination import data")
                case .probe:
                    Text("Navigation succeeded")
                        .navigationTitle("Settings probe")
                        .onAppear { log.info("Settings probe destination appeared") }
                }
            }
            .navigationDiagnostics("Settings root form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        log.info("Settings Done requested")
                        dismiss()
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
        .onChange(of: path.count) { previous, current in
            log.info("Settings path rendered: \(previous) → \(current)")
        }
    }

    private var navigationPathBinding: Binding<NavigationPath> {
        Binding(get: { path }, set: { updated in
            log.info("Settings framework path write: \(path.count) → \(updated.count)")
            path = updated
        })
    }

    private func open(_ destination: Destination) {
        log.info("Settings action requested: \(destination.rawValue) depth=\(path.count)")
        path.append(destination)
        log.info("Settings path appended: \(destination.rawValue) depth=\(path.count)")
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
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
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            disclosureIndicator
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }
}
