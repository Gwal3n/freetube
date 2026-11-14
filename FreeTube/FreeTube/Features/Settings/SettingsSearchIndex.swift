import Foundation

enum SettingsSearchIndex {
    enum Destination: String {
        case playback, player, captions, browsing, appearance, libraryData, cache, downloads
        case privacy, community, diagnostics, about
        case playbackSpeeds, playerControls, subscriptionGroups, channelTabs
        case tabBar, importExport, incognito, blockedContent

        var section: String {
            switch self {
            case .playback: return String(localized: "Playback")
            case .player: return String(localized: "Player")
            case .captions: return String(localized: "Captions")
            case .browsing: return String(localized: "Browsing")
            case .appearance: return String(localized: "Appearance")
            case .libraryData: return String(localized: "Library & Data")
            case .cache: return String(localized: "Cache")
            case .downloads: return String(localized: "Downloads")
            case .privacy: return String(localized: "Privacy")
            case .community: return String(localized: "SponsorBlock & DeArrow")
            case .diagnostics: return String(localized: "Diagnostics")
            case .about: return String(localized: "About")
            case .playbackSpeeds:
                return String(localized: "Playback") + " › " + String(localized: "Playback speeds")
            case .playerControls:
                return String(localized: "Player") + " › " + String(localized: "Top controls layout")
            case .subscriptionGroups:
                return String(localized: "Browsing") + " › " + String(localized: "Subscription groups")
            case .channelTabs:
                return String(localized: "Browsing") + " › " + String(localized: "Channel tabs")
            case .tabBar:
                return String(localized: "Appearance") + " › " + String(localized: "Tab Bar")
            case .importExport:
                return String(localized: "Import & Export")
            case .incognito:
                return String(localized: "Privacy") + " › " + String(localized: "Incognito")
            case .blockedContent:
                return String(localized: "Privacy") + " › " + String(localized: "Blocked content")
            }
        }
    }

    struct Entry: Identifiable {
        let title: LocalizedStringResource
        let destination: Destination

        var displayTitle: String { String(localized: title) }
        var id: String { "\(destination.rawValue):\(displayTitle)" }

        var focusTitle: String? {
            switch destination {
            case .appearance where displayTitle == String(localized: "System")
                || displayTitle == String(localized: "Light")
                || displayTitle == String(localized: "Dark"):
                return String(localized: "Theme")
            case .appearance where displayTitle == String(localized: "Accent color"):
                return UserDefaults.standard.bool(forKey: "useAccentTheme")
                    ? String(localized: "Accent color") : String(localized: "Use accent colors")
            case .appearance where displayTitle == String(localized: "Navigation bars only")
                && !UserDefaults.standard.bool(forKey: "useAccentTheme"):
                return String(localized: "Use accent colors")
            case .appearance where displayTitle == String(localized: "Custom accent color"):
                return UserDefaults.standard.string(forKey: "appAccentPreset") == AppAccentPreset.custom.rawValue
                    && UserDefaults.standard.bool(forKey: "useAccentTheme")
                    ? String(localized: "Custom accent color") : String(localized: "Use accent colors")
            case .tabBar where displayTitle == String(localized: "Tab Bar"):
                return String(localized: "Show tab names")
            case .browsing where displayTitle == String(localized: "Browsing"):
                return String(localized: "Show search suggestions")
            case .libraryData where displayTitle == String(localized: "Library & Data"):
                return String(localized: "Save watch history")
            case .downloads where displayTitle == String(localized: "Downloads"):
                return String(localized: "Default quality")
            case .privacy where displayTitle == String(localized: "Privacy"):
                return String(localized: "Incognito")
            case .diagnostics where displayTitle == String(localized: "Diagnostics"):
                return String(localized: "Save logs to file")
            case .cache where displayTitle == String(localized: "Cache"):
                return String(localized: "Cache recent video details")
            case .importExport where displayTitle == String(localized: "Import & Export"):
                return String(localized: "Export All Settings and Data")
            case .playbackSpeeds where displayTitle == String(localized: "Playback speeds"):
                return String(localized: "Default playback speed")
            case .playerControls where displayTitle == String(localized: "Top controls layout")
                || displayTitle == String(localized: "Customize controls"):
                return String(localized: "On player")
            case .playback where displayTitle == String(localized: "Playback"):
                return String(localized: "Default quality")
            case .player where displayTitle == String(localized: "Player"):
                return String(localized: "Double-tap seek")
            case .player where displayTitle == String(localized: "Seek amount")
                && UserDefaults.standard.string(forKey: "transportButtonMode") != "seek":
                return String(localized: "Transport buttons")
            case .player where displayTitle == String(localized: "Custom scrubber color")
                && UserPreferences().playerScrubberColorModeRaw != PlayerScrubberColorMode.custom.rawValue:
                return String(localized: "Scrubber color")
            case .playback where [
                String(localized: "Speed indicator"),
                String(localized: "Auto-hide indicator"),
                String(localized: "Hide after")
            ].contains(displayTitle) && !UserPreferences().holdForSpeedEnabled:
                return String(localized: "Hold to speed up")
            case .playback where (displayTitle == String(localized: "Auto-hide indicator")
                || displayTitle == String(localized: "Hide after"))
                && UserPreferences().holdSpeedIndicatorStyleRaw == HoldSpeedIndicatorStyle.none.rawValue:
                return String(localized: "Speed indicator")
            case .playback where displayTitle == String(localized: "Hide after")
                && !UserPreferences().holdSpeedIndicatorAutoHide:
                return String(localized: "Auto-hide indicator")
            case .captions where displayTitle == String(localized: "Captions"):
                return String(localized: "Dark background")
            case .player where (displayTitle == String(localized: "Left side")
                || displayTitle == String(localized: "Right side"))
                && UserPreferences().playerVerticalSwipeAction != .adjustPlayback:
                return String(localized: "Vertical swipe in fullscreen")
            case .player where displayTitle == String(localized: "Collapsed description preview")
                && !UserPreferences().showDescription:
                return String(localized: "Show description")
            case .player where displayTitle == String(localized: "Featured comment preview")
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where (displayTitle == String(localized: "Show commenter photos")
                || displayTitle == String(localized: "Tap commenter to open channel")
                || displayTitle == String(localized: "Load more as you scroll")
                || displayTitle == String(localized: "Pin Comments heading"))
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where displayTitle == String(localized: "Videos shown at first")
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .player where displayTitle == String(localized: "Thumbnail size")
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .player where (displayTitle == String(localized: "Show channel avatars")
                || displayTitle == String(localized: "Tap channel to open")
                || displayTitle == String(localized: "Pin Up Next heading"))
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .browsing where displayTitle == String(localized: "Refresh interval")
                && !UserPreferences().automaticFeedRefreshEnabled:
                return String(localized: "Refresh automatically")
            case .browsing where displayTitle == String(localized: "View count interval")
                && !UserPreferences().automaticFeedViewCountsEnabled:
                return String(localized: "Refresh view counts")
            case .browsing where (displayTitle == String(localized: "Gap for same channel")
                || displayTitle == String(localized: "Gap for same group")
                || displayTitle == String(localized: "Max time window"))
                && !UserPreferences().spaceSubscriptionFeedVideos:
                return String(localized: "Space out related videos")
            case .browsing where (displayTitle == String(localized: "Progress color")
                || displayTitle == String(localized: "Custom progress color")
                || displayTitle == String(localized: "Finished videos"))
                && !UserPreferences().showHistoryProgressBars:
                return String(localized: "Show watch progress")
            case .libraryData where (displayTitle == String(localized: "Shelf content")
                || displayTitle == String(localized: "Videos on shelf"))
                && (!UserPreferences().showLibraryShelf || !UserPreferences().saveWatchHistory):
                return String(localized: "Show video shelf")
            case .community where displayTitle == String(localized: "Random frame if none submitted")
                && !UserPreferences().deArrowThumbnails:
                return String(localized: "Replace thumbnails")
            case .community where displayTitle == String(localized: "Show original toggle")
                && !(UserPreferences().deArrowTitles || UserPreferences().deArrowThumbnails):
                return String(localized: "Replace titles")
            case .community where displayTitle == String(localized: "Segment colors")
                && !UserPreferences().sponsorBlockEnabled:
                return String(localized: "SponsorBlock")
            case .community where displayTitle == String(localized: "SponsorBlock & DeArrow"):
                return String(localized: "SponsorBlock")
            case .cache where displayTitle == String(localized: "Prefetch details and comments")
                && !UserDefaults.standard.bool(forKey: "cacheRecentVideoContent"):
                return String(localized: "Cache recent video details")
            case .blockedContent where displayTitle == String(localized: "Blocked content"):
                return String(localized: "Hide Shorts")
            default:
                return displayTitle
            }
        }
    }

    private struct Group {
        let destination: Destination
        let titles: [LocalizedStringResource]
    }

    private static let groups: [Group] = [
        Group(destination: .playback, titles: [
            "Playback", "Default quality", "On cellular", "Sleep timer durations", "Hold to speed up", "Hold speed",
            "Speed indicator", "Auto-hide indicator", "Hide after",
            "Autoplay next video", "Mix with other audio", "Resume after interruptions"
        ]),
        Group(destination: .player, titles: [
            "Player", "Tap video to play or pause", "Swipe to seek", "Double-tap seek", "Seek preview",
            "Vertical swipe in fullscreen", "Left side", "Right side",
            "Show Save button", "Show Share button", "Show Download button", "Scrubber color", "Custom scrubber color",
            "Remember mini player position", "Transport buttons", "Seek amount", "Show description",
            "Collapsed description preview",
            "Show comments", "Pin Comments heading", "Load more as you scroll", "Show commenter photos",
            "Tap commenter to open channel", "Featured comment preview", "Show Up Next",
            "Pin Up Next heading", "Show channel avatars", "Tap channel to open", "Thumbnail size",
            "Videos shown at first", "Pin Queue heading", "Reorder sections", "Top controls layout"
        ]),
        Group(destination: .captions, titles: [
            "Captions", "Dark background", "Keep original formatting", "Text size"
        ]),
        Group(destination: .playbackSpeeds, titles: [
            "Playback speeds", "Default playback speed", "Available speeds"
        ]),
        Group(destination: .playerControls, titles: [
            "Top controls layout", "On player", "More menu", "Hidden",
            "More menu separators", "Fine seeking", "Quality", "Playback details", "Captions"
        ]),
        Group(destination: .browsing, titles: [
            "Browsing", "Show search suggestions", "Load more as you scroll",
            "Large thumbnails", "Show channel avatars", "Show watch progress", "Progress color",
            "Custom progress color", "Finished videos", "Tap channel to open", "Show filter button",
            "Load more videos as you scroll", "Include suggested videos", "Suggestion density",
            "Mark new uploads", "Space out related videos",
            "Gap for same channel", "Gap for same group", "Max time window", "Refresh automatically",
            "Refresh interval", "Refresh view counts", "View count interval"
        ]),
        Group(destination: .subscriptionGroups, titles: ["Subscription groups"]),
        Group(destination: .channelTabs, titles: ["Channel tabs"]),
        Group(destination: .appearance, titles: [
            "Appearance", "Theme", "System", "Light", "Dark", "Use accent colors", "Navigation bars only",
            "Accent color", "Custom accent color", "Text font", "Lock portrait while browsing"
        ]),
        Group(destination: .tabBar, titles: ["Tab Bar", "Show tab names", "Visible tabs & order"]),
        Group(destination: .libraryData, titles: [
            "Library & Data", "Save watch history", "Add when a video opens",
            "Keep history for", "Clear Watch Progress", "Clear Watch History", "Show Continue Watching",
            "Show video shelf", "Shelf content", "Videos on shelf"
        ]),
        Group(destination: .cache, titles: [
            "Cache", "Cache recent video details", "Prefetch details and comments", "Cache recent channels",
            "Storage used", "Clear recent video cache", "Clear recent channel cache", "Clear all temporary caches"
        ]),
        Group(destination: .importExport, titles: [
            "Import & Export", "Export All Settings and Data", "Import Full Backup",
            "Export Subscriptions CSV", "Import Subscriptions CSV", "Export Playlists",
            "Import Playlist Archive", "Import Playlist CSV Files"
        ]),
        Group(destination: .downloads, titles: [
            "Downloads", "Default quality", "Allow cellular downloads", "Simultaneous connections"
        ]),
        Group(destination: .privacy, titles: [
            "Privacy", "Save recent searches", "Searches to keep", "Save recent channels", "Channels to keep"
        ]),
        Group(destination: .incognito, titles: [
            "Incognito", "Don't save searches", "Don't save watch history",
            "Don't save watch progress", "Hide watch progress bars", "Hide Feed tab", "Hide Library tab"
        ]),
        Group(destination: .blockedContent, titles: ["Blocked content", "Hide Shorts", "Blocked keywords", "Blocked channels"]),
        Group(destination: .community, titles: [
            "SponsorBlock & DeArrow", "SponsorBlock", "Segment colors", "Channel whitelist",
            "Full-video label on thumbnail", "Full-video label under seek bar",
            "Minimum length to auto-skip",
            "Undo banner duration", "Replace titles", "Replace thumbnails",
            "Random frame if none submitted", "Show original toggle", "Sponsors", "Self-promotion",
            "Exclusive access", "Interaction reminders", "Intros", "Outros", "Previews",
            "Hooks and greetings", "Non-music sections", "Filler", "Highlights",
            "Community chapters"
        ]),
        Group(destination: .diagnostics, titles: [
            "Diagnostics", "Save logs to file", "Log player scroll timing", "Share latest log…",
            "Show log folder", "Clear all logs"
        ]),
        Group(destination: .about, titles: ["About"])
    ]

    static func results(matching query: String) -> [Entry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return groups.flatMap { group in
            group.titles.map { Entry(title: $0, destination: group.destination) }
        }
        .filter { entry in
            words.allSatisfy { entry.displayTitle.localizedStandardContains($0) }
        }
    }
}
