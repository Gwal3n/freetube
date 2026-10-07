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
    var saveWatchHistory: Bool {
        didSet { preferences.saveWatchHistory = saveWatchHistory }
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
    var sponsorBlockEnabled: Bool {
        didSet { preferences.sponsorBlockEnabled = sponsorBlockEnabled }
    }
    var playerControlLayout: PlayerControlLayout {
        didSet { preferences.playerControlLayout = playerControlLayout }
    }
    var playerMoreMenuDividers: Set<PlayerTopControl> {
        didSet { preferences.playerMoreMenuDividers = playerMoreMenuDividers }
    }
    var appFontPreset: AppFontPreset {
        didSet { preferences.appFontPreset = appFontPreset }
    }
    var captionBackgroundEnabled: Bool {
        didSet { preferences.captionBackgroundEnabled = captionBackgroundEnabled }
    }
    var captionTextScale: Double {
        didSet { preferences.captionTextScale = captionTextScale }
    }
    var formattedCaptions: Bool {
        didSet { preferences.formattedCaptions = formattedCaptions }
    }
    var automaticFeedRefreshEnabled: Bool {
        didSet { preferences.automaticFeedRefreshEnabled = automaticFeedRefreshEnabled }
    }
    var automaticFeedRefreshInterval: FeedRefreshInterval {
        didSet { preferences.automaticFeedRefreshInterval = automaticFeedRefreshInterval }
    }

    init() {
        let preferences = UserPreferences()
        self.preferences = preferences
        self.upNextInitialCount = preferences.upNextInitialCount
        self.showUpNext = preferences.showUpNext
        self.saveWatchHistory = preferences.saveWatchHistory
        self.deArrowTitles = preferences.deArrowTitles
        self.deArrowThumbnails = preferences.deArrowThumbnails
        self.deArrowRandomThumbnails = preferences.deArrowRandomThumbnails
        self.sponsorBlockEnabled = preferences.sponsorBlockEnabled
        self.playerControlLayout = preferences.playerControlLayout
        self.playerMoreMenuDividers = preferences.playerMoreMenuDividers
        self.appFontPreset = preferences.appFontPreset
        self.captionBackgroundEnabled = preferences.captionBackgroundEnabled
        self.captionTextScale = preferences.captionTextScale
        self.formattedCaptions = preferences.formattedCaptions
        self.automaticFeedRefreshEnabled = preferences.automaticFeedRefreshEnabled
        self.automaticFeedRefreshInterval = preferences.automaticFeedRefreshInterval
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

    var showNewSubscriptionUploads: Bool {
        get { preferences.showNewSubscriptionUploads }
        set { preferences.showNewSubscriptionUploads = newValue }
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
        let current = playerControlLayout
        var layout = current
        layout.move(control, to: section, before: target)
        guard layout != current else { return }
        playerControlLayout = layout
    }

    func reorderPlayerControls(
        in section: PlayerControlLayout.Section,
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) {
        var layout = playerControlLayout
        layout.reorder(in: section, fromOffsets: offsets, toOffset: destination)
        guard layout != playerControlLayout else { return }
        playerControlLayout = layout
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

    var concurrentFragments: Int {
        get { preferences.concurrentFragments }
        set { preferences.concurrentFragments = newValue }
    }
}
