import Foundation
import Observation
import SwiftUI

@available(iOS 17.0, *)
@Observable
@MainActor
final class SettingsViewModel {
    var preferences: UserPreferences
    /// Stored observable value so the Stepper's trailing count redraws immediately. Writing only
    /// through `@AppStorage` on a nested value persists correctly but does not notify @Observable.
    var upNextInitialCount: Int {
        didSet { preferences.upNextInitialCount = upNextInitialCount }
    }
    var showUpNext: Bool {
        didSet { preferences.showUpNext = showUpNext }
    }
    var deArrowTitles: Bool {
        didSet { preferences.deArrowTitles = deArrowTitles }
    }
    var deArrowThumbnails: Bool {
        didSet { preferences.deArrowThumbnails = deArrowThumbnails }
    }
    var deArrowRandomThumbnails: Bool {
        didSet { preferences.deArrowRandomThumbnails = deArrowRandomThumbnails }
    }
    var playerControlLayout: PlayerControlLayout {
        didSet { preferences.playerControlLayout = playerControlLayout }
    }

    init() {
        let preferences = UserPreferences()
        self.preferences = preferences
        self.upNextInitialCount = preferences.upNextInitialCount
        self.showUpNext = preferences.showUpNext
        self.deArrowTitles = preferences.deArrowTitles
        self.deArrowThumbnails = preferences.deArrowThumbnails
        self.deArrowRandomThumbnails = preferences.deArrowRandomThumbnails
        self.playerControlLayout = preferences.playerControlLayout
    }

    var preferredQuality: VideoQuality {
        get { preferences.preferredQuality }
        set { preferences.preferredQuality = newValue }
    }

    var appearanceMode: AppearanceMode {
        get { preferences.appearanceMode }
        set { preferences.appearanceMode = newValue }
    }

    var allowCellularDownloads: Bool {
        get { preferences.allowCellularDownloads }
        set { preferences.allowCellularDownloads = newValue }
    }

    var alwaysDownloadBeforePlayback: Bool {
        get { preferences.alwaysDownloadBeforePlayback }
        set { preferences.alwaysDownloadBeforePlayback = newValue }
    }

    var autoplayNext: Bool {
        get { preferences.autoplayNext }
        set { preferences.autoplayNext = newValue }
    }

    var verticalSwipeFullscreen: Bool {
        get { preferences.verticalSwipeFullscreen }
        set { preferences.verticalSwipeFullscreen = newValue }
    }

    var showHistoryProgressBars: Bool {
        get { preferences.showHistoryProgressBars }
        set { preferences.showHistoryProgressBars = newValue }
    }

    var historyRetentionPolicy: HistoryRetentionPolicy {
        get { preferences.historyRetentionPolicy }
        set {
            preferences.historyRetentionPolicy = newValue
            if let cutoff = newValue.cutoffDate() {
                Task { await PersistenceWriter.shared.clearWatchHistory(olderThan: cutoff) }
            }
        }
    }

    func clearLocalHistory() {
        Task { await PersistenceWriter.shared.clearWatchHistory() }
    }

    var showSubscriptionFeedTab: Bool {
        get { preferences.showSubscriptionFeedTab }
        set { preferences.showSubscriptionFeedTab = newValue }
    }

    var largeSubscriptionFeedThumbnails: Bool {
        get { preferences.largeSubscriptionFeedThumbnails }
        set { preferences.largeSubscriptionFeedThumbnails = newValue }
    }

    var showComments: Bool {
        get { preferences.showComments }
        set { preferences.showComments = newValue }
    }

    var showDescription: Bool {
        get { preferences.showDescription }
        set { preferences.showDescription = newValue }
    }

    var showSearchSuggestions: Bool {
        get { preferences.showSearchSuggestions }
        set { preferences.showSearchSuggestions = newValue }
    }

    var showFeaturedCommentPreview: Bool {
        get { preferences.showFeaturedCommentPreview }
        set { preferences.showFeaturedCommentPreview = newValue }
    }

    var prefetchVideoDetails: Bool {
        get { preferences.prefetchVideoDetails }
        set { preferences.prefetchVideoDetails = newValue }
    }

    var allowAudioMixing: Bool {
        get { preferences.allowAudioMixing }
        set {
            preferences.allowAudioMixing = newValue
            AudioSessionConfigurator.configure(allowMixing: newValue, activate: false)
        }
    }

    var oledPlayerBackground: Bool {
        get { preferences.oledPlayerBackground }
        set { preferences.oledPlayerBackground = newValue }
    }

    var oledMiniPlayer: Bool {
        get { preferences.oledMiniPlayer }
        set { preferences.oledMiniPlayer = newValue }
    }

    func movePlayerControl(
        _ control: PlayerTopControl,
        to section: PlayerControlLayout.Section,
        before target: PlayerTopControl? = nil
    ) {
        var layout = playerControlLayout
        layout.move(control, to: section, before: target)
        playerControlLayout = layout
    }

    var sponsorBlockEnabled: Bool {
        get { preferences.sponsorBlockEnabled }
        set { preferences.sponsorBlockEnabled = newValue }
    }

    func sponsorBlockBehaviorBinding(for category: SponsorBlockCategory) -> Binding<SponsorBlockBehavior> {
        Binding(
            get: { self.preferences.sponsorBlockBehavior(for: category) },
            set: { self.preferences.setSponsorBlockBehavior($0, for: category) }
        )
    }

    // MARK: - Diagnostics

    /// Two-way binding for the "Save logs to file" toggle. Routes through
    /// `LogFileWriter.shared.setEnabled(_:)` so the writer starts/stops in addition to the
    /// persisted flag flipping — otherwise the toggle would change state on disk but
    /// nothing would actually start capturing until the next launch.
    var logToFile: Bool {
        get { LogFileWriter.shared.isEnabled }
        set { LogFileWriter.shared.setEnabled(newValue) }
    }

    /// Convenience pass-through so the Settings view doesn't need to import the writer
    /// directly when binding actions to its state.
    var currentLogFileURL: URL? { LogFileWriter.shared.currentLogFileURL }

    func clearLogFiles() {
        LogFileWriter.shared.clearAllLogs()
    }

    var downloadCacheLimit: DownloadCacheLimit {
        get { preferences.downloadCacheLimit }
        set {
            preferences.downloadCacheLimit = newValue
            // Apply the new cap immediately so the user doesn't have to download a new video to
            // see eviction kick in. `DownloadsStore.enforceCacheLimit` no-ops on `.unlimited`
            // (nil bytes) and posts the change notification once files have been removed.
            DownloadsStore.shared.enforceCacheLimit(
                newValue.bytes,
                protectedVideoIDs: PlaylistDownloadCoordinator.shared.protectedVideoIDs
            )
        }
    }

    var concurrentFragments: Int {
        get { preferences.concurrentFragments }
        set { preferences.concurrentFragments = newValue }
    }

    // MARK: - yt-dlp updater

    /// Currently-loaded yt-dlp version (e.g. `"2026.3.17"`). Empty until `YtDlpUpdater` has run
    /// at least once — the package's own first-run download happens before that, but the
    /// updater is what reads `__version__` back. Empty-string fallback keeps the Settings row
    /// renderable even when this hasn't been populated yet.
    var ytDlpVersion: String { preferences.ytDlpVersion }

    /// Display string for the last successful yt-dlp refresh, formatted in the user's locale.
    /// `nil` ⇒ "Never" in the UI (initial-install state before the TTL check has fired).
    var ytDlpLastUpdatedDisplay: String? {
        guard let date = preferences.lastYtDlpUpdate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Drives the "Update now" button — disable while a refresh is in flight (either the
    /// launch-time TTL one or a previous user tap).
    var isUpdatingYtDlp: Bool { YtDlpUpdater.shared.isUpdating }

    /// Status line shown beneath the button: success / no-change / failure / hidden.
    var ytDlpUpdateStatus: YtDlpUpdater.UpdateResult? { YtDlpUpdater.shared.lastResult }

    /// User tapped "Update now". Forwards to the shared updater; the awaiting Task runs to
    /// completion even if the user leaves the Settings screen (we want the version row to
    /// reflect the new value when they come back).
    func updateYtDlpNow() {
        Task { await YtDlpUpdater.shared.updateNow() }
    }
}
