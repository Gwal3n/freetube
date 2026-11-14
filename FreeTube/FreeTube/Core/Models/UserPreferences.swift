import Foundation
import SwiftUI

/// Lightweight user preferences stored in `UserDefaults` via `@AppStorage`. Use this for primitive flags only;
/// anything queryable belongs in SwiftData.
struct UserPreferences {
    @AppStorage("preferredQuality") var preferredQualityRaw: String = VideoQuality.p360.rawValue
    /// Migrated once from the old shared quality preference.
    @AppStorage("defaultDownloadQuality") var defaultDownloadQualityRaw: String = VideoQuality.p360.rawValue
    @AppStorage("cellularPlaybackQuality") var cellularPlaybackQualityRaw: String = VideoQuality.auto.rawValue
    @AppStorage("seekPreviewStyle") var seekPreviewStyleRaw: String = SeekPreviewStyle.compact.rawValue
    @AppStorage("doubleTapSeekSeconds") var doubleTapSeekSeconds: Int = 10
    @AppStorage("resumeAfterAudioInterruption") var resumeAfterAudioInterruption: Bool = true
    @AppStorage("rememberFloatingPlayerPlacement") var rememberFloatingPlayerPlacement: Bool = false
    @AppStorage("floatingPlayerWidth") private var savedFloatingPlayerWidthRaw: Double = 216
    /// Replaces the inverted legacy `wifiOnlyDownloads` key.
    @AppStorage("allowCellularDownloads") var allowCellularDownloads: Bool = true
    @AppStorage("autoplayNext") var autoplayNext: Bool = true
    @AppStorage("verticalSwipeFullscreen") var verticalSwipeFullscreen: Bool = true
    @AppStorage("verticalSwipeAdjustments") var verticalSwipeAdjustments: Bool = false
    @AppStorage("leftFullscreenSwipeAction") var leftFullscreenSwipeActionRaw: String = PlayerSwipeAdjustmentAction.brightness.rawValue
    @AppStorage("rightFullscreenSwipeAction") var rightFullscreenSwipeActionRaw: String = PlayerSwipeAdjustmentAction.volume.rawValue
    @AppStorage("showHistoryProgressBars") var showHistoryProgressBars: Bool = true
    @AppStorage("saveWatchHistory") var saveWatchHistory: Bool = true
    @AppStorage("addToHistoryWhenOpened") var addToHistoryWhenOpened: Bool = false
    @AppStorage("historyRetentionPolicy") var historyRetentionPolicyRaw: String = HistoryRetentionPolicy.forever.rawValue
    @AppStorage("showSubscriptionFeedTab") var showSubscriptionFeedTab: Bool = true
    @AppStorage("largeSubscriptionFeedThumbnails") var largeSubscriptionFeedThumbnails: Bool = false
    @AppStorage("showFeedChannelAvatars") var showFeedChannelAvatars: Bool = true
    @AppStorage("openFeedChannelsOnTap") var openFeedChannelsOnTap: Bool = false
    @AppStorage("showNewSubscriptionUploads") var showNewSubscriptionUploads: Bool = true
    @AppStorage("spaceSubscriptionFeedVideos") var spaceSubscriptionFeedVideos: Bool = true
    @AppStorage("feedSuggestionsEnabled") var feedSuggestionsEnabled: Bool = false
    @AppStorage("feedSuggestionDensity") var feedSuggestionDensity: Int = 10
    @AppStorage("feedChannelSpacing") var feedChannelSpacing: Int = 2
    @AppStorage("feedGroupSpacing") var feedGroupSpacing: Int = 2
    @AppStorage("feedSpacingMaximumShiftHours") var feedSpacingMaximumShiftHours: Int = 24
    @AppStorage("automaticFeedRefreshEnabled") var automaticFeedRefreshEnabled: Bool = false
    @AppStorage("automaticFeedRefreshInterval") var automaticFeedRefreshIntervalRaw: String = FeedRefreshInterval.everySixHours.rawValue
    @AppStorage("automaticFeedViewCountsEnabled") var automaticFeedViewCountsEnabled: Bool = false
    @AppStorage("automaticFeedViewCountInterval") var automaticFeedViewCountIntervalRaw: String = FeedRefreshInterval.hourly.rawValue
    @AppStorage("showComments") var showComments: Bool = true
    @AppStorage("showDescription") var showDescription: Bool = true
    @AppStorage("showCollapsedDescriptionPreview") var showCollapsedDescriptionPreview: Bool = true
    @AppStorage("showFeaturedCommentPreview") var showFeaturedCommentPreview: Bool = false
    @AppStorage("featuredCommentsNearPlaybackOnly") var featuredCommentsNearPlaybackOnly: Bool = false
    @AppStorage("showCommentAuthorPhotos") var showCommentAuthorPhotos: Bool = true
    @AppStorage("openCommentAuthorChannels") var openCommentAuthorChannels: Bool = false
    @AppStorage("showUpNext") var showUpNext: Bool = true
    @AppStorage("showUpNextChannelAvatars") var showUpNextChannelAvatars: Bool = false
    @AppStorage("openUpNextChannelsOnTap") var openUpNextChannelsOnTap: Bool = false
    @AppStorage("showSearchSuggestions") var showSearchSuggestions: Bool = true
    @AppStorage("saveSearchHistory") var saveSearchHistory: Bool = true
    @AppStorage("saveRecentChannels") var saveRecentChannels: Bool = true
    @AppStorage("incognitoEnabled") var incognitoEnabled: Bool = false
    @AppStorage("incognitoSkipSearchHistory") var incognitoSkipSearchHistory: Bool = true
    @AppStorage("incognitoSkipWatchHistory") var incognitoSkipWatchHistory: Bool = true
    @AppStorage("incognitoSkipWatchProgress") var incognitoSkipWatchProgress: Bool = true
    @AppStorage("incognitoHideWatchProgress") var incognitoHideWatchProgress: Bool = true
    @AppStorage("incognitoHideFeed") var incognitoHideFeed: Bool = false
    @AppStorage("incognitoHideLibrary") var incognitoHideLibrary: Bool = false
    @AppStorage("upNextInitialCount") var upNextInitialCount: Int = 5
    @AppStorage("prefetchVideoDetails") var prefetchVideoDetails: Bool = true
    @AppStorage("cacheRecentVideoContent") var cacheRecentVideoContent: Bool = true
    @AppStorage("cacheRecentChannelContent") var cacheRecentChannelContent: Bool = true
    @AppStorage("allowAudioMixing") var allowAudioMixing: Bool = false
    @AppStorage("captionBackgroundEnabled") var captionBackgroundEnabled: Bool = true
    @AppStorage("captionTextScale") var captionTextScale: Double = 1.0
    @AppStorage("formattedCaptions") var formattedCaptions: Bool = true
    @AppStorage("com.leshko.freetube.deArrowTitles") var deArrowTitles: Bool = false
    @AppStorage("com.leshko.freetube.deArrowThumbnails") var deArrowThumbnails: Bool = false
    @AppStorage("com.leshko.freetube.deArrowRandomThumbnails") var deArrowRandomThumbnails: Bool = true
    @AppStorage("com.leshko.freetube.deArrowShowOriginalToggle") var deArrowShowOriginalToggle: Bool = true
    @AppStorage("playerTopControlOrder") var playerTopControlOrderRaw: String = PlayerTopControl.encodeOrder(PlayerTopControl.defaultOrder)
    @AppStorage("hiddenPlayerTopControls") var hiddenPlayerTopControlsRaw: String = ""
    @AppStorage("playerControlLayout") var playerControlLayoutRaw: String = ""
    @AppStorage("playerMoreMenuDividers") var playerMoreMenuDividersRaw: String = ""
    @AppStorage("logToFile") var logToFile: Bool = false
    @AppStorage("appearanceMode") var appearanceModeRaw: String = AppearanceMode.dark.rawValue
    @AppStorage("appAccentPreset") var appAccentPresetRaw: String = AppAccentPreset.classic.rawValue
    @AppStorage("appFontPreset") var appFontPresetRaw: String = AppFontPreset.system.rawValue
    @AppStorage("concurrentFragments") var concurrentFragments: Int = 4
    /// Distinct from the legacy per-video `playbackRate` key; defaults to 1x.
    @AppStorage("defaultPlaybackRate") var defaultPlaybackRate: Double = 1.0
    @AppStorage("customPlaybackSpeeds") var customPlaybackSpeedsRaw: String = ""
    @AppStorage("holdForSpeedEnabled") var holdForSpeedEnabled: Bool = true
    @AppStorage("centerTapPlayPauseEnabled") var centerTapPlayPauseEnabled: Bool = false
    @AppStorage("holdSpeedRate") var holdSpeedRate: Double = 2.0
    @AppStorage(HoldSpeedIndicatorStyle.storageKey) var holdSpeedIndicatorStyleRaw: String = HoldSpeedIndicatorStyle.storedDefault
    @AppStorage(HoldSpeedIndicatorStyle.autoHideKey) var holdSpeedIndicatorAutoHide: Bool = false
    @AppStorage(HoldSpeedIndicatorStyle.hideDelayKey) var holdSpeedIndicatorHideDelay: Double = HoldSpeedIndicatorStyle.defaultHideDelay
    @AppStorage("playerScrubberColorMode") var playerScrubberColorModeRaw: String = PlayerScrubberColorMode.standard.rawValue
    @AppStorage("playerScrubberCustomHex") var playerScrubberCustomHex: String = "#FF0000"
    @AppStorage("sponsorBlockColorOverridesJSON") var sponsorBlockColorOverridesJSON: String = "{}"
    @AppStorage("showLibraryShelf") var showLibraryShelf: Bool = true
    @AppStorage("showContinueWatchingMenu") var showContinueWatchingMenu: Bool = true
    @AppStorage("libraryShelfContent") var libraryShelfContentRaw: String = LibraryShelfContent.continueWatching.rawValue
    @AppStorage("recentLibraryVideoCount") var recentLibraryVideoCount: Int = 5
    @AppStorage("sponsorBlockEnabled") var sponsorBlockEnabled: Bool = false
    @AppStorage("sponsorBlockMinimumSkipSeconds") var sponsorBlockMinimumSkipSeconds: Double = 0
    @AppStorage("sponsorBlockNoticeSeconds") var sponsorBlockNoticeSeconds: Double = 5
    @AppStorage("sponsorBlockSponsorBehavior") var sponsorBlockSponsorBehaviorRaw: String = SponsorBlockBehavior.autoSkip.rawValue
    @AppStorage("sponsorBlockSelfPromotionBehavior") var sponsorBlockSelfPromotionBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockExclusiveAccessBehavior") var sponsorBlockExclusiveAccessBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockInteractionBehavior") var sponsorBlockInteractionBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockIntroBehavior") var sponsorBlockIntroBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockOutroBehavior") var sponsorBlockOutroBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockPreviewBehavior") var sponsorBlockPreviewBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockHookBehavior") var sponsorBlockHookBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockMusicOfftopicBehavior") var sponsorBlockMusicOfftopicBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockFillerBehavior") var sponsorBlockFillerBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    @AppStorage("sponsorBlockHighlightBehavior") var sponsorBlockHighlightBehaviorRaw: String = SponsorBlockBehavior.ask.rawValue
    @AppStorage("sponsorBlockChapterBehavior") var sponsorBlockChapterBehaviorRaw: String = SponsorBlockBehavior.disabled.rawValue
    /// Corner badge on the player thumbnail for full-video SponsorBlock labels.
    @AppStorage("sponsorBlockShowFullVideoThumbnailBadge") var sponsorBlockShowFullVideoThumbnailBadge: Bool = true
    /// Colored stripe under the seek bar for full-video labels. Off by default.
    @AppStorage("sponsorBlockShowFullVideoSeekStripe") var sponsorBlockShowFullVideoSeekStripe: Bool = false
    /// Channel IDs that skip SponsorBlock lookups entirely.
    @AppStorage("sponsorBlockChannelWhitelistJSON") var sponsorBlockChannelWhitelistJSON: String = "[]"

    // MARK: - Catalogued screen preferences

    @AppStorage("useAccentTheme") var useAccentTheme: Bool = false
    @AppStorage("accentNavigationOnly") var accentNavigationOnly: Bool = false
    @AppStorage("appCustomAccentHex") var appCustomAccentHex: String = "#FF3B30"
    @AppStorage(OrientationPolicy.lockKey) var portraitOrientationLock: Bool = false
    @AppStorage("showFeedFilterButton") var showFeedFilterButton: Bool = true
    @AppStorage("autoLoadMoreFeedItems") var autoLoadMoreFeedItems: Bool = true
    @AppStorage("autoLoadMoreSearchItems") var autoLoadMoreSearchItems: Bool = true
    @AppStorage("autoLoadMoreComments") var autoLoadMoreComments: Bool = true
    @AppStorage("showLibraryTab") var showLibraryTab: Bool = true
    @AppStorage("showDownloadsTab") var showDownloadsTab: Bool = true
    @AppStorage("showSearchTab") var showSearchTab: Bool = true
    @AppStorage("showSettingsTab") var showSettingsTab: Bool = true
    @AppStorage("showTabBarLabels") var showTabBarLabels: Bool = true
    @AppStorage("tabBarOrder") var tabBarOrderRaw: String = "feed,library,downloads,settings"
    @AppStorage("showChannelAboutTab") var showChannelAboutTab: Bool = true
    @AppStorage("showChannelLiveTab") var showChannelLiveTab: Bool = true
    @AppStorage("showChannelPlaylistsTab") var showChannelPlaylistsTab: Bool = true
    @AppStorage("showChannelShortsTab") var showChannelShortsTab: Bool = true
    @AppStorage("showPlayerDownloadButton") var showPlayerDownloadButton: Bool = true
    @AppStorage("showPlayerSaveButton") var showPlayerSaveButton: Bool = true
    @AppStorage("showPlayerShareButton") var showPlayerShareButton: Bool = true
    @AppStorage("pinCommentsHeading") var pinCommentsHeading: Bool = false
    @AppStorage("pinUpNextHeading") var pinUpNextHeading: Bool = false
    @AppStorage("pinQueueHeading") var pinQueueHeading: Bool = false
    @AppStorage("playerScrollDiagnosticsEnabled") var playerScrollDiagnosticsEnabled: Bool = false
    @AppStorage("horizontalSwipeToSeekEnabled") var horizontalSwipeToSeekEnabled: Bool = true
    @AppStorage("customDoubleTapSeekSeconds") var customDoubleTapSeekSeconds: Int = 20
    @AppStorage("transportButtonMode") var transportButtonModeRaw: String = ""
    @AppStorage("transportSeekSeconds") var transportSeekSeconds: Int = 10
    @AppStorage("upNextRowSize") var upNextRowSizeRaw: String = UpNextRowSize.compact.rawValue
    @AppStorage("playerPanelSectionOrder") var playerPanelSectionOrderRaw: String = ""
    @AppStorage("playbackSpeedChoices") var playbackSpeedChoicesRaw: String = ""
    @AppStorage("sleepTimerMinuteChoices") var sleepTimerMinuteChoicesRaw: String = ""
    @AppStorage("watchProgressColorMode") var watchProgressColorModeRaw: String = ""
    @AppStorage("watchProgressCustomHex") var watchProgressCustomHex: String = "#FF0000"
    @AppStorage("finishedVideoIndicator") var finishedVideoIndicatorRaw: String = ""
    @AppStorage("floatingPlayerCorner") var floatingPlayerCornerRaw: String = "bottomTrailing"
    @AppStorage("floatingPlayerVerticalFraction") var floatingPlayerVerticalFraction: Double = 1
    @AppStorage("recentChannelsJSON") var recentChannelsJSON: String = "[]"
    @AppStorage(RecentHistoryLimits.searchKey) var recentSearchLimit: Int = RecentHistoryLimits.defaultSearchLimit
    @AppStorage(RecentHistoryLimits.channelKey) var recentChannelLimit: Int = RecentHistoryLimits.defaultChannelLimit

    init() {
        let defaults = UserDefaults.standard
        // Channel visits previously followed the search-history switch. Preserve an existing
        // opt-out when introducing their independent setting.
        if defaults.object(forKey: "saveRecentChannels") == nil {
            defaults.set(defaults.object(forKey: "saveSearchHistory") as? Bool ?? true,
                         forKey: "saveRecentChannels")
        }
        guard defaults.object(forKey: "defaultDownloadQuality") == nil else { return }
        let previous = defaults.string(forKey: "preferredQuality") ?? VideoQuality.p360.rawValue
        defaults.set(
            (VideoQuality(rawValue: previous) ?? .p360).rawValue,
            forKey: "defaultDownloadQuality"
        )
    }

    var preferredQuality: VideoQuality {
        get { VideoQuality(rawValue: preferredQualityRaw) ?? .auto }
        nonmutating set { preferredQualityRaw = newValue.rawValue }
    }

    var defaultDownloadQuality: VideoQuality {
        get { VideoQuality(rawValue: defaultDownloadQualityRaw) ?? .p360 }
        nonmutating set { defaultDownloadQualityRaw = newValue.rawValue }
    }

    var cellularPlaybackQuality: VideoQuality {
        get {
            let quality = VideoQuality(rawValue: cellularPlaybackQualityRaw) ?? .auto
            return quality == .audioOnly ? .auto : quality
        }
        nonmutating set { cellularPlaybackQualityRaw = newValue.rawValue }
    }

    var seekPreviewStyle: SeekPreviewStyle {
        get { SeekPreviewStyle(rawValue: seekPreviewStyleRaw) ?? .compact }
        nonmutating set { seekPreviewStyleRaw = newValue.rawValue }
    }

    var savedFloatingPlayerWidth: Double {
        get { savedFloatingPlayerWidthRaw }
        nonmutating set { savedFloatingPlayerWidthRaw = newValue }
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

    var leftFullscreenSwipeAction: PlayerSwipeAdjustmentAction {
        get { PlayerSwipeAdjustmentAction(rawValue: leftFullscreenSwipeActionRaw) ?? .brightness }
        nonmutating set { leftFullscreenSwipeActionRaw = newValue.rawValue }
    }

    var rightFullscreenSwipeAction: PlayerSwipeAdjustmentAction {
        get { PlayerSwipeAdjustmentAction(rawValue: rightFullscreenSwipeActionRaw) ?? .volume }
        nonmutating set { rightFullscreenSwipeActionRaw = newValue.rawValue }
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

    var appAccentPreset: AppAccentPreset {
        get { AppAccentPreset(rawValue: appAccentPresetRaw) ?? .classic }
        nonmutating set { appAccentPresetRaw = newValue.rawValue }
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
        case .exclusiveAccess: raw = sponsorBlockExclusiveAccessBehaviorRaw
        case .interaction: raw = sponsorBlockInteractionBehaviorRaw
        case .intro: raw = sponsorBlockIntroBehaviorRaw
        case .outro: raw = sponsorBlockOutroBehaviorRaw
        case .preview: raw = sponsorBlockPreviewBehaviorRaw
        case .hook: raw = sponsorBlockHookBehaviorRaw
        case .musicOfftopic: raw = sponsorBlockMusicOfftopicBehaviorRaw
        case .filler: raw = sponsorBlockFillerBehaviorRaw
        case .highlight: raw = sponsorBlockHighlightBehaviorRaw
        case .chapter: raw = sponsorBlockChapterBehaviorRaw
        }
        let behavior = SponsorBlockBehavior(rawValue: raw) ?? .disabled
        // Earlier builds offered Auto skip for full-video labels. Preserve that user's enabled
        // choice without ever seeking to the end of a video or treating chapters as skip ranges.
        return SponsorBlockBehavior.choices(for: category).contains(behavior) ? behavior : .showOnly
    }

    mutating func setSponsorBlockBehavior(_ behavior: SponsorBlockBehavior, for category: SponsorBlockCategory) {
        switch category {
        case .sponsor: sponsorBlockSponsorBehaviorRaw = behavior.rawValue
        case .selfPromotion: sponsorBlockSelfPromotionBehaviorRaw = behavior.rawValue
        case .exclusiveAccess: sponsorBlockExclusiveAccessBehaviorRaw = behavior.rawValue
        case .interaction: sponsorBlockInteractionBehaviorRaw = behavior.rawValue
        case .intro: sponsorBlockIntroBehaviorRaw = behavior.rawValue
        case .outro: sponsorBlockOutroBehaviorRaw = behavior.rawValue
        case .preview: sponsorBlockPreviewBehaviorRaw = behavior.rawValue
        case .hook: sponsorBlockHookBehaviorRaw = behavior.rawValue
        case .musicOfftopic: sponsorBlockMusicOfftopicBehaviorRaw = behavior.rawValue
        case .filler: sponsorBlockFillerBehaviorRaw = behavior.rawValue
        case .highlight: sponsorBlockHighlightBehaviorRaw = behavior.rawValue
        case .chapter: sponsorBlockChapterBehaviorRaw = behavior.rawValue
        }
    }

    var sponsorBlockWhitelistedChannelIDs: [String] {
        get {
            guard let data = sponsorBlockChannelWhitelistJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return ids.filter { !$0.isEmpty }
        }
        nonmutating set {
            let unique = Array(Set(newValue.filter { !$0.isEmpty })).sorted()
            guard let data = try? JSONEncoder().encode(unique),
                  let json = String(data: data, encoding: .utf8) else {
                sponsorBlockChannelWhitelistJSON = "[]"
                return
            }
            sponsorBlockChannelWhitelistJSON = json
        }
    }

    func isSponsorBlockWhitelisted(channelID: String?) -> Bool {
        guard let channelID, !channelID.isEmpty else { return false }
        return sponsorBlockWhitelistedChannelIDs.contains(channelID)
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .dark }
        nonmutating set { appearanceModeRaw = newValue.rawValue }
    }

    var automaticFeedRefreshInterval: FeedRefreshInterval {
        get { FeedRefreshInterval(rawValue: automaticFeedRefreshIntervalRaw) ?? .everySixHours }
        nonmutating set { automaticFeedRefreshIntervalRaw = newValue.rawValue }
    }

    var automaticFeedViewCountInterval: FeedRefreshInterval {
        get { FeedRefreshInterval(rawValue: automaticFeedViewCountIntervalRaw) ?? .hourly }
        nonmutating set { automaticFeedViewCountIntervalRaw = newValue.rawValue }
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
