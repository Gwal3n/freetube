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
            case .captions where displayTitle == String(localized: "Captions"):
                return String(localized: "Dark caption background")
            case .player where (displayTitle == String(localized: "Left side")
                || displayTitle == String(localized: "Right side"))
                && UserPreferences().playerVerticalSwipeAction != .adjustPlayback:
                return String(localized: "Vertical swipe in fullscreen")
            case .player where displayTitle == String(localized: "Show featured comment preview")
                && !UserPreferences().showComments:
                return String(localized: "Show comments")
            case .player where displayTitle == String(localized: "Initial Up Next videos")
                && !UserPreferences().showUpNext:
                return String(localized: "Show Up Next")
            case .browsing where displayTitle == String(localized: "Refresh interval")
                && !UserPreferences().automaticFeedRefreshEnabled:
                return String(localized: "Refresh feed automatically")
            case .libraryData where (displayTitle == String(localized: "Shelf content")
                || displayTitle == String(localized: "Shelf videos"))
                && (!UserPreferences().showLibraryShelf || !UserPreferences().saveWatchHistory):
                return String(localized: "Library video shelf")
            case .community where displayTitle == String(localized: "Random thumbnail when no submission exists")
                && !UserPreferences().deArrowThumbnails:
                return String(localized: "Replace video thumbnails")
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
            "Playback", "Default playback quality", "Cellular streaming limit", "Hold for speed", "Hold speed",
            "Autoplay next video", "Allow audio from other apps", "Resume after interruptions"
        ]),
        Group(destination: .player, titles: [
            "Player", "Double-tap seek", "Seek preview", "Vertical swipe in fullscreen", "Left side", "Right side",
            "Remember floating player placement", "Show watch progress bars", "Show description",
            "Show comments", "Show featured comment preview", "Show Up Next",
            "Initial Up Next videos", "Prefetch details and comments"
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
            "Browsing", "Show search suggestions", "Save recent searches",
            "Large video thumbnails", "Mark new uploads", "Refresh feed automatically",
            "Refresh interval"
        ]),
        Group(destination: .subscriptionGroups, titles: ["Manage subscription groups"]),
        Group(destination: .channelTabs, titles: ["Channel tabs"]),
        Group(destination: .appearance, titles: ["Appearance", "System", "Light", "Dark", "Accent color", "Text font"]),
        Group(destination: .tabBar, titles: ["Tab Bar", "Show tab names", "Tab order"]),
        Group(destination: .libraryData, titles: [
            "Library & Data", "Save watch history", "Add to history when opened",
            "Keep watch history", "Clear Watch Progress", "Clear Watch History", "Continue Watching in Library",
            "Library video shelf", "Shelf content", "Shelf videos"
        ]),
        Group(destination: .cache, titles: [
            "Cache", "Cache recent video details", "Clear recent video cache", "Clear all temporary caches"
        ]),
        Group(destination: .importExport, titles: [
            "Import & Export", "Export All Settings and Data", "Import Full Backup",
            "Export Subscriptions CSV", "Import Subscriptions CSV", "Export Local Playlists",
            "Import Playlist Archive", "Import Playlist CSV Files"
        ]),
        Group(destination: .downloads, titles: ["Downloads", "Default download quality", "Allow cellular data", "Parallel fragments"]),
        Group(destination: .privacy, titles: ["Privacy"]),
        Group(destination: .incognito, titles: [
            "Incognito", "Don't save searches", "Don't save watch history",
            "Don't save watch progress", "Hide watch progress", "Hide Feed tab", "Hide Library tab"
        ]),
        Group(destination: .blockedContent, titles: ["Blocked content", "Hide Shorts", "Blocked keywords", "Blocked channels"]),
        Group(destination: .community, titles: [
            "SponsorBlock & DeArrow", "Enable SponsorBlock", "Minimum segment length",
            "Skip notice duration", "Replace video titles", "Replace video thumbnails",
            "Random thumbnail when no submission exists", "Sponsors", "Self-promotion",
            "Exclusive access", "Interaction reminders", "Intros", "Outros", "Previews",
            "Hooks and greetings", "Non-music sections", "Filler", "Highlights",
            "Community chapters"
        ]),
        Group(destination: .diagnostics, titles: [
            "Diagnostics", "Save logs to file", "Share latest log…", "Show log folder", "Clear all logs"
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
