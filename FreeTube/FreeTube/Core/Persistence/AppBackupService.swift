import CoreFoundation
import Foundation
import SwiftData

@available(iOS 17.0, *)
@MainActor
final class AppBackupService {
    static let shared = AppBackupService()

    private let playlists = LocalPlaylistService()
    private let context = ModelContext(PersistenceController.sharedContainer)

    private init() {}

    func makeBackup() async throws -> AppBackup {
        var playlistRecords: [AppBackup.PlaylistRecord] = []
        for playlist in await playlists.playlists() {
            guard let details = await playlists.details(id: playlist.id) else { continue }
            playlistRecords.append(AppBackup.PlaylistRecord(
                localID: playlist.id,
                title: playlist.title,
                descriptionText: playlist.descriptionText,
                sourcePlaylistID: playlist.sourcePlaylistID,
                videos: details.videos,
                customArtworkData: playlist.customArtworkData
            ))
        }

        let searches = (try? context.fetch(FetchDescriptor<SearchHistoryEntry>())) ?? []
        let favoriteVideos = (try? context.fetch(FetchDescriptor<FavoriteVideo>())) ?? []
        let favoritePlaylists = (try? context.fetch(FetchDescriptor<FavoritePlaylist>())) ?? []
        var backup = AppBackup(
            formatVersion: 1,
            exportedAt: .now,
            settings: exportedSettings(),
            subscriptions: LocalSubscriptionStore.shared.subscriptions,
            playlists: playlistRecords,
            watchHistory: await PersistenceWriter.shared.allWatchHistory(),
            searchHistory: searches.map { .init(query: $0.query, searchedAt: $0.searchedAt) },
            favoriteVideos: favoriteVideos.map {
                .init(videoID: $0.videoID, title: $0.title, channelName: $0.channelName, thumbnailURL: $0.thumbnailURL, savedAt: $0.savedAt)
            },
            favoritePlaylists: favoritePlaylists.map {
                .init(playlistID: $0.playlistID, title: $0.title, channelName: $0.channelName, thumbnailURL: $0.thumbnailURL, videoCount: $0.videoCount, savedAt: $0.savedAt)
            }
        )
        backup.subscriptionGroups = LocalSubscriptionGroupStore.shared.groups
        backup.savedMoments = SavedMomentStore.shared.moments
        return backup
    }

    func encode(_ backup: AppBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    func decode(_ data: Data) throws -> AppBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)
        guard backup.formatVersion == 1 else { throw BackupError.unsupportedVersion }
        return backup
    }

    func restore(_ backup: AppBackup) async throws {
        guard backup.formatVersion == 1 else { throw BackupError.unsupportedVersion }

        let existing = await playlists.playlists()
        await playlists.delete(ids: Set(existing.map(\.id)))
        var restoredPlaylistIDs: [String] = []
        var remappedLocalPlaylistIDs: [String: String] = [:]
        for playlist in backup.playlists {
            let id = await LocalPlaylistWriter.shared.replace(
                title: playlist.title,
                descriptionText: playlist.descriptionText,
                sourcePlaylistID: playlist.sourcePlaylistID,
                videos: playlist.videos
            )
            await playlists.setArtwork(id: id, data: playlist.customArtworkData)
            restoredPlaylistIDs.append(id)
            if let oldID = playlist.localID {
                remappedLocalPlaylistIDs[oldID] = id
            }
        }
        await playlists.reorderPlaylists(restoredPlaylistIDs)
        await PersistenceWriter.shared.replaceWatchHistory(
            with: backup.watchHistory,
            remappedLocalPlaylistIDs: remappedLocalPlaylistIDs
        )

        replaceSwiftData(backup)
        LocalSubscriptionStore.shared.replaceAll(with: backup.subscriptions)
        LocalSubscriptionGroupStore.shared.replaceAll(
            with: backup.subscriptionGroups ?? [],
            validChannelIDs: Set(backup.subscriptions.map(\.id))
        )
        // An older backup cannot describe this newer collection. Keep current moments in that
        // case; a new backup exports an explicit empty array when the user has none.
        if let savedMoments = backup.savedMoments {
            SavedMomentStore.shared.replaceAll(with: savedMoments)
        }
        restoreSettings(backup.settings)
        VideoBlocklist.shared.reload()
    }

    private func replaceSwiftData(_ backup: AppBackup) {
        for item in (try? context.fetch(FetchDescriptor<SearchHistoryEntry>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<FavoriteVideo>())) ?? [] { context.delete(item) }
        for item in (try? context.fetch(FetchDescriptor<FavoritePlaylist>())) ?? [] { context.delete(item) }
        try? context.save()
        for item in backup.searchHistory { context.insert(SearchHistoryEntry(query: item.query, searchedAt: item.searchedAt)) }
        for item in backup.favoriteVideos {
            context.insert(FavoriteVideo(videoID: item.videoID, title: item.title, channelName: item.channelName, thumbnailURL: item.thumbnailURL, savedAt: item.savedAt))
        }
        for item in backup.favoritePlaylists {
            context.insert(FavoritePlaylist(playlistID: item.playlistID, title: item.title, channelName: item.channelName, thumbnailURL: item.thumbnailURL, videoCount: item.videoCount, savedAt: item.savedAt))
        }
        try? context.save()
    }

    private func exportedSettings() -> [String: AppBackup.SettingValue] {
        let defaults = UserDefaults.standard
        return Dictionary(uniqueKeysWithValues: Self.settingKeys.compactMap { key in
            guard let value = defaults.object(forKey: key) else { return nil }
            if let value = value as? String { return (key, .text(value)) }
            if let value = value as? NSNumber {
                return CFGetTypeID(value) == CFBooleanGetTypeID()
                    ? (key, .boolean(value.boolValue))
                    : (key, value.doubleValue.rounded() == value.doubleValue
                        ? .integer(value.intValue)
                        : .number(value.doubleValue))
            }
            return nil
        })
    }

    private func restoreSettings(_ settings: [String: AppBackup.SettingValue]) {
        let defaults = UserDefaults.standard
        for key in Self.settingKeys { defaults.removeObject(forKey: key) }
        for (key, value) in settings where Self.settingKeys.contains(key) {
            switch value {
            case .boolean(let value): defaults.set(value, forKey: key)
            case .integer(let value): defaults.set(value, forKey: key)
            case .number(let value): defaults.set(value, forKey: key)
            case .text(let value): defaults.set(value, forKey: key)
            }
        }
        if settings["saveRecentChannels"] == nil {
            defaults.set(defaults.object(forKey: "saveSearchHistory") as? Bool ?? true,
                         forKey: "saveRecentChannels")
        }
    }

    private static let settingKeys: Set<String> = [
        "addToHistoryWhenOpened", "allowAudioMixing", "allowCellularDownloads", "alwaysDownloadBeforePlayback", "appAccentPreset", "appFontPreset",
        "automaticFeedRefreshEnabled", "automaticFeedRefreshInterval", "automaticFeedViewCountsEnabled", "automaticFeedViewCountInterval", "cacheRecentVideoContent", "cellularPlaybackQuality",
        "spaceSubscriptionFeedVideos", "feedChannelSpacing", "feedGroupSpacing", "feedSpacingMaximumShiftHours",
        "com.leshko.freetube.videoBlocklist.v1",
        "appearanceMode", "useAccentTheme", "accentNavigationOnly", "appCustomAccentHex", "tabBarOrder", "showTabBarLabels", "showLibraryTab", "showDownloadsTab", "showSearchTab", "showSettingsTab", "autoplayNext", "captionBackgroundEnabled", "captionTextScale",
        "concurrentFragments", "customDoubleTapSeekSeconds", "customPlaybackSpeeds", "playbackSpeedChoices", "sleepTimerMinuteChoices", "defaultDownloadQuality", "defaultPlaybackRate", "doubleTapSeekSeconds", "formattedCaptions",
        "floatingPlayerWidth", "floatingPlayerCorner", "floatingPlayerVerticalFraction",
        "com.leshko.freetube.deArrowTitles", "com.leshko.freetube.deArrowThumbnails",
        "com.leshko.freetube.deArrowRandomThumbnails",
        "hiddenPlayerTopControls", "historyRetentionPolicy", "holdForSpeedEnabled", "holdSpeedRate", "horizontalSwipeToSeekEnabled",
        "largeSubscriptionFeedThumbnails",
        "incognitoSkipSearchHistory", "incognitoSkipWatchHistory", "incognitoSkipWatchProgress",
        "incognitoHideWatchProgress", "incognitoHideFeed", "incognitoHideLibrary",
        "logToFile", "manualQueue",
        "playerControlLayout", "playerMoreMenuDividers", "playerTopControlOrder",
        "libraryShelfContent", "leftFullscreenSwipeAction", "recentLibraryVideoCount", "rightFullscreenSwipeAction",
        "preferredQuality", "prefetchVideoDetails", "rememberFloatingPlayerPlacement", "resumeAfterAudioInterruption",
        "saveSearchHistory", "saveRecentChannels", "recentChannelsJSON", "saveWatchHistory", "seekPreviewStyle", "showChannelAboutTab", "showChannelLiveTab", "showPlayerDownloadButton", "showPlayerSaveButton", "showPlayerShareButton",
        "showChannelPlaylistsTab", "showChannelShortsTab", "showComments", "showDescription", "showFeaturedCommentPreview", "featuredCommentsNearPlaybackOnly",
        "showCommentAuthorPhotos", "openCommentAuthorChannels",
        "showContinueWatchingMenu", "showHistoryProgressBars", "watchProgressColorMode", "watchProgressCustomHex", "finishedVideoIndicator", "transportButtonMode", "transportSeekSeconds", "showLibraryShelf", "showNewSubscriptionUploads", "showSearchSuggestions", "showSubscriptionFeedTab", "showUpNext", "sponsorBlockEnabled",
        "sponsorBlockHighlightBehavior", "sponsorBlockInteraction", "sponsorBlockInteractionBehavior",
        "sponsorBlockExclusiveAccessBehavior", "sponsorBlockPreviewBehavior",
        "sponsorBlockHookBehavior", "sponsorBlockChapterBehavior",
        "sponsorBlockMusicOfftopicBehavior", "sponsorBlockFillerBehavior",
        "sponsorBlockIntro", "sponsorBlockIntroBehavior", "sponsorBlockOutro",
        "sponsorBlockOutroBehavior", "sponsorBlockSelfPromotion", "sponsorBlockSelfPromotionBehavior",
        "sponsorBlockMinimumSkipSeconds", "sponsorBlockNoticeSeconds",
        "sponsorBlockSponsor", "sponsorBlockSponsorBehavior", "upNextInitialCount"
    ]

    enum BackupError: LocalizedError {
        case unsupportedVersion
        var errorDescription: String? { "This backup was created by an unsupported app version." }
    }
}
