import Foundation

/// Searchable labels for the existing Settings pages. Results navigate to the owning page;
/// controls and their state remain owned by those pages rather than duplicated in search.
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
            case .community: return String(localized: "Community enhancements")
            case .diagnostics: return String(localized: "Diagnostics")
            case .about: return String(localized: "About")
            case .playbackSpeeds:
                return String(localized: "Playback") + " › " + String(localized: "Playback speeds")
            case .playerControls:
                return String(localized: "Player") + " › " + String(localized: "Customize controls")
            case .subscriptionGroups:
                return String(localized: "Browsing") + " › " + String(localized: "Manage subscription groups")
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

        /// Picker values and page names point at their owning control instead of a missing row.
        var focusTitle: String? {
            switch destination {
            case .appearance where displayTitle == String(localized: "System")
                || displayTitle == String(localized: "Light")
                || displayTitle == String(localized: "Dark"):
                return String(localized: "Appearance")
            case .appearance where displayTitle == String(localized: "Accent color"):
                return UserDefaults.standard.bool(forKey: "useAccentTheme")
                    ? String(localized: "Accent color") : String(localized: "Use accent colors")
            case .appearance where displayTitle == String(localized: "Accent navigation bar only")
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
                return String(localized: "Default download quality")
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
            case .playerControls where displayTitle == String(localized: "Customize controls"):
                return String(localized: "On player")
            case .playback where displayTitle == String(localized: "Playback"):
                return String(localized: "Default playback quality")
            case .player where displayTitle == String(localized: "Player"):
                return String(localized: "Double-tap seek")
            case .player where displayTitle == String(localized: "Seek button interval")
                && UserDefaults.standard.string(forKey: "transportButtonMode") != "seek":
                return String(localized: "Transport buttons")
            case .player where displayTitle == String(localized: "Custom scrubber color")
                && UserPreferences().playerScrubberColorModeRaw != PlayerScrubberColorMode.custom.rawValue:
                return String(localized: "Scrubber color")
            case .playback where displayTitle == String(localized: "Show hold-speed pill")
                && !UserPreferences().holdForSpeedEnabled:
                return String(localized: "Hold for speed")
            case .captions where displayTitle == String(localized: "Captions"):
                return String(localized: "Dark caption background")
            case .player where (displayTitle == String(localized: "Left side")
                || displayTitle == String(localized: "Right side"))
                && UserPreferences().playerVerticalSwipeAction != .adjustPlayback:
                return String(localized: "Vertical swipe in fullscreen")
            case .player where displayTitle == String(localized: "Featured comment preview")
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where (displayTitle == String(localized: "Show commenter photos")
                || displayTitle == String(localized: "Open commenter channels"))
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where (displayTitle == String(localized: "Load more comments automatically")
                || displayTitle == String(localized: "Keep comments heading visible"))
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where displayTitle == String(localized: "Initial Up Next videos")
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .player where displayTitle == String(localized: "Up Next video size")
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .player where (displayTitle == String(localized: "Show channel avatars in Up Next")
                || displayTitle == String(localized: "Open Up Next channels from name or avatar"))
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .browsing where displayTitle == String(localized: "Refresh interval")
                && !UserPreferences().automaticFeedRefreshEnabled:
                return String(localized: "Refresh feed automatically")
            case .browsing where displayTitle == String(localized: "View count batch interval")
                && !UserPreferences().automaticFeedViewCountsEnabled:
                return String(localized: "Update feed view counts")
            case .browsing where (displayTitle == String(localized: "Same channel gap")
                || displayTitle == String(localized: "Same group gap")
                || displayTitle == String(localized: "Maximum date shift"))
                && !UserPreferences().spaceSubscriptionFeedVideos:
                return String(localized: "Space out related uploads")
            case .libraryData where (displayTitle == String(localized: "Shelf content")
                || displayTitle == String(localized: "Shelf videos"))
                && (!UserPreferences().showLibraryShelf || !UserPreferences().saveWatchHistory):
                return String(localized: "Library video shelf")
            case .community where displayTitle == String(localized: "Random thumbnail when no submission exists")
                && !UserPreferences().deArrowThumbnails:
                return String(localized: "Replace video thumbnails")
            case .community where displayTitle == String(localized: "Segment colors")
                && !UserPreferences().sponsorBlockEnabled:
                return String(localized: "Enable SponsorBlock")
            case .community where displayTitle == String(localized: "SponsorBlock & DeArrow"):
                return String(localized: "Enable SponsorBlock")
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

    // The visible control labels are intentionally listed here rather than extracting Form text
    // at runtime. SwiftUI views do not expose a reliable searchable control hierarchy.
    private static let groups: [Group] = [
        Group(destination: .playback, titles: [
            "Playback", "Default playback quality", "Cellular streaming limit", "Sleep timer durations", "Hold for speed", "Hold speed", "Show hold-speed pill",
            "Autoplay next video", "Allow audio from other apps", "Resume after interruptions"
        ]),
        Group(destination: .player, titles: [
            "Player", "Swipe horizontally to seek", "Double-tap seek", "Seek preview", "Vertical swipe in fullscreen", "Left side", "Right side",
            "Save button", "Share button", "Download button", "Scrubber color", "Custom scrubber color",
            "Remember floating player placement", "Show watch progress bars", "Watch progress color", "Fully watched videos", "Transport buttons", "Seek button interval", "Show description",
            "Show comments", "Keep comments heading visible", "Load more comments automatically", "Show commenter photos", "Open commenter channels", "Featured comment preview", "Show Up Next",
            "Initial Up Next videos", "Up Next video size", "Show channel avatars in Up Next", "Open Up Next channels from name or avatar", "Rearrange sections", "Prefetch details and comments"
        ]),
        Group(destination: .captions, titles: [
            "Captions", "Dark caption background", "Use source formatting", "Caption text size"
        ]),
        Group(destination: .playbackSpeeds, titles: [
            "Playback speeds", "Default playback speed", "Available speeds"
        ]),
        Group(destination: .playerControls, titles: [
            "Customize controls", "On player", "More menu", "Hidden",
            "More menu separators", "Fine seeking", "Quality limit", "Captions"
        ]),
        Group(destination: .browsing, titles: [
            "Browsing", "Show search suggestions", "Load more search results automatically",
            "Large video thumbnails", "Show channel avatars", "Open feed channels from name or avatar", "Load more feed videos automatically", "Mark new uploads", "Space out related uploads",
            "Same channel gap", "Same group gap", "Maximum date shift", "Refresh feed automatically",
            "Refresh interval", "Update feed view counts", "View count batch interval"
        ]),
        Group(destination: .subscriptionGroups, titles: ["Manage subscription groups"]),
        Group(destination: .channelTabs, titles: ["Channel tabs"]),
        Group(destination: .appearance, titles: ["Appearance", "System", "Light", "Dark", "Use accent colors", "Accent navigation bar only", "Accent color", "Custom accent color", "Text font"]),
        Group(destination: .tabBar, titles: ["Tab Bar", "Show tab names", "Tab order"]),
        Group(destination: .libraryData, titles: [
            "Library & Data", "Save watch history", "Add to history when opened",
            "Keep watch history", "Clear Watch Progress", "Clear Watch History", "Continue Watching in Library",
            "Library video shelf", "Shelf content", "Shelf videos"
        ]),
        Group(destination: .cache, titles: [
            "Cache", "Cache recent video details", "Storage used", "Clear recent video cache",
            "Clear all temporary caches"
        ]),
        Group(destination: .importExport, titles: [
            "Import & Export", "Export All Settings and Data", "Import Full Backup",
            "Export Subscriptions CSV", "Import Subscriptions CSV", "Export Local Playlists",
            "Import Playlist Archive", "Import Playlist CSV Files"
        ]),
        Group(destination: .downloads, titles: ["Downloads", "Default download quality", "Allow cellular data", "Parallel fragments"]),
        Group(destination: .privacy, titles: ["Privacy", "Save recent searches", "Save recent channels"]),
        Group(destination: .incognito, titles: [
            "Incognito", "Don't save searches", "Don't save watch history",
            "Don't save watch progress", "Hide watch progress", "Hide Feed tab", "Hide Library tab"
        ]),
        Group(destination: .blockedContent, titles: ["Blocked content", "Hide Shorts", "Blocked keywords", "Blocked channels"]),
        Group(destination: .community, titles: [
            "SponsorBlock & DeArrow", "Enable SponsorBlock", "Segment colors", "Minimum segment length",
            "Skip notice duration", "Replace video titles", "Replace video thumbnails",
            "Random thumbnail when no submission exists", "Sponsors", "Self-promotion",
            "Exclusive access", "Interaction reminders", "Intros", "Outros", "Previews",
            "Hooks and greetings", "Non-music sections", "Filler", "Highlights",
            "Community chapters"
        ]),
        Group(destination: .diagnostics, titles: [
            "Diagnostics", "Save logs to file", "Measure player scrolling", "Share latest log…", "Show log folder", "Clear all logs"
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
