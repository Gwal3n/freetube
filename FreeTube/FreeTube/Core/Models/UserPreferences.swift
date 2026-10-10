import Foundation
import SwiftUI

/// Lightweight user preferences stored in `UserDefaults` via `@AppStorage`. Use this for primitive flags only;
/// anything queryable belongs in SwiftData.
struct UserPreferences {
    /// Default to 360p on a fresh install — it's the only YouTube format that ships as a single
    /// combined progressive mp4 (itag 18), so downloads complete fast and skip the Swift-side
    /// ffmpeg mux step. Users can bump it higher in Settings.
    @AppStorage("preferredQuality") var preferredQualityRaw: String = VideoQuality.p360.rawValue
    @AppStorage("alwaysDownloadBeforePlayback") var alwaysDownloadBeforePlayback: Bool = false
    /// When `true`, downloads (and playback-time fetches, since those use the same path) are
    /// allowed to run over cellular. Default is `true` — permissive — so a fresh install
    /// works out of the box on a phone without Wi-Fi. Users who pay per MB can disable this
    /// and the network gate in `DownloadManager.waitForAllowedNetwork` will throw until
    /// Wi-Fi comes back. Was previously stored under the `wifiOnlyDownloads` key with the
    /// opposite meaning (true = blocked on cellular); fresh key here so the default flips
    /// cleanly for existing installs.
    @AppStorage("allowCellularDownloads") var allowCellularDownloads: Bool = true
    @AppStorage("autoplayNext") var autoplayNext: Bool = true
    /// Enables the existing swipe-up entry and swipe-down fullscreen exit. Retained to preserve
    /// the user's prior on/off choice when adding the fullscreen-only adjustment mode.
    @AppStorage("verticalSwipeFullscreen") var verticalSwipeFullscreen: Bool = true
    @AppStorage("verticalSwipeAdjustments") var verticalSwipeAdjustments: Bool = false
    /// Shows locally stored resume progress along video thumbnails throughout the app.
    @AppStorage("showHistoryProgressBars") var showHistoryProgressBars: Bool = true
    /// Stops writing local watch history and playback positions when disabled. Existing entries
    /// remain available until the user clears them explicitly.
    @AppStorage("saveWatchHistory") var saveWatchHistory: Bool = true
    @AppStorage("historyRetentionPolicy") var historyRetentionPolicyRaw: String = HistoryRetentionPolicy.forever.rawValue
    /// Removes the local-subscription Feed destination from the tab bar when disabled. Cached
    /// entries remain on device so restoring the tab is immediate and does not force a refresh.
    @AppStorage("showSubscriptionFeedTab") var showSubscriptionFeedTab: Bool = true
    /// Uses edge-to-edge 16:9 cards in the local subscription feed instead of compact rows.
    @AppStorage("largeSubscriptionFeedThumbnails") var largeSubscriptionFeedThumbnails: Bool = false
    /// Shows a quiet New label for subscription uploads estimated after the previous app visit.
    @AppStorage("showNewSubscriptionUploads") var showNewSubscriptionUploads: Bool = true
    /// Opt-in, foreground-only refresh of the local subscription feed.
    @AppStorage("automaticFeedRefreshEnabled") var automaticFeedRefreshEnabled: Bool = false
    @AppStorage("automaticFeedRefreshInterval") var automaticFeedRefreshIntervalRaw: String = FeedRefreshInterval.everySixHours.rawValue
    @AppStorage("showComments") var showComments: Bool = true
    @AppStorage("showDescription") var showDescription: Bool = true
    /// Shows YouTube's comments-entry teaser beneath the collapsed Comments heading. If YouTubeKit
    /// cannot decode the current teaser shape, the first top-level comment is used as a fallback.
    @AppStorage("showFeaturedCommentPreview") var showFeaturedCommentPreview: Bool = false
    @AppStorage("showUpNext") var showUpNext: Bool = true
    @AppStorage("showSearchSuggestions") var showSearchSuggestions: Bool = true
    @AppStorage("saveSearchHistory") var saveSearchHistory: Bool = true
    /// Incognito keeps existing local data intact while changing what this session records or shows.
    @AppStorage("incognitoEnabled") var incognitoEnabled: Bool = false
    @AppStorage("incognitoSkipSearchHistory") var incognitoSkipSearchHistory: Bool = true
    @AppStorage("incognitoSkipWatchHistory") var incognitoSkipWatchHistory: Bool = true
    @AppStorage("incognitoSkipWatchProgress") var incognitoSkipWatchProgress: Bool = true
    @AppStorage("incognitoHideWatchProgress") var incognitoHideWatchProgress: Bool = true
    @AppStorage("incognitoHideFeed") var incognitoHideFeed: Bool = false
    @AppStorage("incognitoHideLibrary") var incognitoHideLibrary: Bool = false
    @AppStorage("upNextInitialCount") var upNextInitialCount: Int = 5
    /// Fetches expanded details and the first comments page only after playback is ready. Further
    /// comment pages and replies always remain user initiated.
    @AppStorage("prefetchVideoDetails") var prefetchVideoDetails: Bool = true
    /// Lets FreeTube coexist with audio already playing in another app. The default remains the
    /// normal primary-media behavior, where activating FreeTube interrupts other non-mixable audio.
    @AppStorage("allowAudioMixing") var allowAudioMixing: Bool = false
    @AppStorage("captionBackgroundEnabled") var captionBackgroundEnabled: Bool = true
    @AppStorage("captionTextScale") var captionTextScale: Double = 1.0
    @AppStorage("formattedCaptions") var formattedCaptions: Bool = true
    @AppStorage("com.leshko.freetube.deArrowTitles") var deArrowTitles: Bool = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") var deArrowThumbnails: Bool = false
    @AppStorage("com.leshko.freetube.deArrowRandomThumbnails") var deArrowRandomThumbnails: Bool = true
    @AppStorage("playerTopControlOrder") var playerTopControlOrderRaw: String = PlayerTopControl.encodeOrder(PlayerTopControl.defaultOrder)
    @AppStorage("hiddenPlayerTopControls") var hiddenPlayerTopControlsRaw: String = ""
    @AppStorage("playerControlLayout") var playerControlLayoutRaw: String = ""
    @AppStorage("playerMoreMenuDividers") var playerMoreMenuDividersRaw: String = ""
    /// When true, `LogFileWriter` opens a new file under `Application Support/Logs/` on every app
    /// launch and directly mirrors rendered `AppLog` entries into it. Useful for
    /// capturing diagnostic traces from TestFlight / sideload installs where Console.app
    /// access isn't practical. Defaults off — only a handful of users will ever flip this.
    @AppStorage("logToFile") var logToFile: Bool = false
    /// When true (default), `PlayerStateManager` kicks off a background download of the
    /// next queue item right after the current video starts playing — so Next-tap is
    /// instant. Users who want to save bandwidth (or who tend not to advance through the
    /// queue) can flip this off in Settings.
    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("appFontPreset") var appFontPresetRaw: String = AppFontPreset.system.rawValue
    /// `--concurrent-fragments` value passed to yt-dlp. Higher values fetch more DASH/HLS chunks
    /// in parallel within a single download, cutting wall-clock time. Defaults to 4 — a good
    /// balance for cellular and consumer Wi-Fi. Values above 8 risk YouTube rate-limiting.
    @AppStorage("concurrentFragments") var concurrentFragments: Int = 4
    /// Persisted user-selected playback rate (1.0 = normal speed). The player may temporarily
    /// cap an unsupported source at 2x while preparing an experimental progressive alternative.
    /// `AVPlayer.defaultRate` uses the validated base rate, not a temporary hold override.
    /// Menu and Settings choices write here explicitly; hold gestures never do.
    @AppStorage("playbackRate") var playbackRate: Double = 1.0
    @AppStorage("customPlaybackSpeeds") var customPlaybackSpeedsRaw: String = ""
    @AppStorage("holdForSpeedEnabled") var holdForSpeedEnabled: Bool = true
    @AppStorage("holdSpeedRate") var holdSpeedRate: Double = 2.0
    @AppStorage("showLibraryShelf") var showLibraryShelf: Bool = true
    @AppStorage("showContinueWatchingMenu") var showContinueWatchingMenu: Bool = true
    @AppStorage("libraryShelfContent") var libraryShelfContentRaw: String = LibraryShelfContent.continueWatching.rawValue
    @AppStorage("recentLibraryVideoCount") var recentLibraryVideoCount: Int = 5
    @AppStorage("sponsorBlockEnabled") var sponsorBlockEnabled: Bool = false
    @AppStorage("sponsorBlockSponsor") var sponsorBlockSponsor: Bool = true
    @AppStorage("sponsorBlockSelfPromotion") var sponsorBlockSelfPromotion: Bool = false
    @AppStorage("sponsorBlockInteraction") var sponsorBlockInteraction: Bool = false
    @AppStorage("sponsorBlockIntro") var sponsorBlockIntro: Bool = false
    @AppStorage("sponsorBlockOutro") var sponsorBlockOutro: Bool = false
    @AppStorage("sponsorBlockSponsorBehavior") var sponsorBlockSponsorBehaviorRaw: String = SponsorBlockBehavior.autoSkip.rawValue
    @AppStorage("sponsorBlockSelfPromotionBehavior") var sponsorBlockSelfPromotionBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockInteractionBehavior") var sponsorBlockInteractionBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockIntroBehavior") var sponsorBlockIntroBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockOutroBehavior") var sponsorBlockOutroBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockHighlightBehavior") var sponsorBlockHighlightBehaviorRaw: String = SponsorBlockBehavior.ask.rawValue

    var preferredQuality: VideoQuality {
        get { VideoQuality(rawValue: preferredQualityRaw) ?? .auto }
        nonmutating set { preferredQualityRaw = newValue.rawValue }
    }

    var playerVerticalSwipeAction: PlayerVerticalSwipeAction {
        get {
            if verticalSwipeAdjustments { return .adjustPlayback }
            return verticalSwipeFullscreen ? .fullscreen : .off
        }
        nonmutating set {
            verticalSwipeAdjustments = newValue == .adjustPlayback
            verticalSwipeFullscreen = newValue == .fullscreen
        }
    }

    var recordsSearchHistory: Bool {
        saveSearchHistory && !(incognitoEnabled && incognitoSkipSearchHistory)
    }

    var recordsWatchHistory: Bool {
        saveWatchHistory && !(incognitoEnabled && incognitoSkipWatchHistory)
    }

    var recordsWatchProgress: Bool {
        recordsWatchHistory && !(incognitoEnabled && incognitoSkipWatchProgress)
    }

    var displaysWatchProgress: Bool {
        showHistoryProgressBars && !(incognitoEnabled && incognitoHideWatchProgress)
    }

    var libraryShelfContent: LibraryShelfContent {
        get { LibraryShelfContent(rawValue: libraryShelfContentRaw) ?? .continueWatching }
        nonmutating set { libraryShelfContentRaw = newValue.rawValue }
    }

    var historyRetentionPolicy: HistoryRetentionPolicy {
        get { HistoryRetentionPolicy(rawValue: historyRetentionPolicyRaw) ?? .forever }
        nonmutating set { historyRetentionPolicyRaw = newValue.rawValue }
    }

    var appFontPreset: AppFontPreset {
        get { AppFontPreset(rawValue: appFontPresetRaw) ?? .system }
        nonmutating set { appFontPresetRaw = newValue.rawValue }
    }

    var playerControlLayout: PlayerControlLayout {
        get {
            PlayerControlLayout.restored(
                from: playerControlLayoutRaw,
                legacyOrder: playerTopControlOrderRaw,
                legacyHidden: hiddenPlayerTopControlsRaw
            )
        }
        nonmutating set { playerControlLayoutRaw = newValue.encoded }
    }

    var playerMoreMenuDividers: Set<PlayerTopControl> {
        get { PlayerTopControl.decodeMenuDividers(playerMoreMenuDividersRaw) }
        nonmutating set { playerMoreMenuDividersRaw = PlayerTopControl.encodeMenuDividers(newValue) }
    }

    var sponsorBlockCategories: Set<SponsorBlockCategory> {
        Set(SponsorBlockCategory.allCases.filter { sponsorBlockBehavior(for: $0) != .disabled })
    }

    func sponsorBlockBehavior(for category: SponsorBlockCategory) -> SponsorBlockBehavior {
        let raw: String
        switch category {
        case .sponsor: raw = sponsorBlockSponsorBehaviorRaw
        case .selfPromotion: raw = sponsorBlockSelfPromotionBehaviorRaw
        case .interaction: raw = sponsorBlockInteractionBehaviorRaw
        case .intro: raw = sponsorBlockIntroBehaviorRaw
        case .outro: raw = sponsorBlockOutroBehaviorRaw
        case .highlight: raw = sponsorBlockHighlightBehaviorRaw
        }
        return SponsorBlockBehavior(rawValue: raw) ?? .disabled
    }

    mutating func setSponsorBlockBehavior(_ behavior: SponsorBlockBehavior, for category: SponsorBlockCategory) {
        switch category {
        case .sponsor: sponsorBlockSponsorBehaviorRaw = behavior.rawValue
        case .selfPromotion: sponsorBlockSelfPromotionBehaviorRaw = behavior.rawValue
        case .interaction: sponsorBlockInteractionBehaviorRaw = behavior.rawValue
        case .intro: sponsorBlockIntroBehaviorRaw = behavior.rawValue
        case .outro: sponsorBlockOutroBehaviorRaw = behavior.rawValue
        case .highlight: sponsorBlockHighlightBehaviorRaw = behavior.rawValue
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        nonmutating set { appearanceModeRaw = newValue.rawValue }
    }

    var automaticFeedRefreshInterval: FeedRefreshInterval {
        get { FeedRefreshInterval(rawValue: automaticFeedRefreshIntervalRaw) ?? .everySixHours }
        nonmutating set { automaticFeedRefreshIntervalRaw = newValue.rawValue }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
