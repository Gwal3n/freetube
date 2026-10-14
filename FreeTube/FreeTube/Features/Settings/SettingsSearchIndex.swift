import Foundation

/// Searchable labels for the existing Settings pages. Results navigate to the owning page;
/// controls and their state remain owned by those pages rather than duplicated in search.
enum SettingsSearchIndex {
    enum Destination: String {
        case playback, browsing, appearance, libraryData, downloads
        case privacy, community, diagnostics, about
        case playbackSpeeds, playerControls, subscriptionGroups, channelTabs
        case tabBar, importExport, incognito, blockedContent

        var section: String {
            switch self {
            case .playback: return String(localized: "Playback")
            case .browsing: return String(localized: "Browsing")
            case .appearance: return String(localized: "Appearance")
            case .libraryData: return String(localized: "Library & Data")
            case .downloads: return String(localized: "Downloads")
            case .privacy: return String(localized: "Privacy")
            case .community: return String(localized: "Community enhancements")
            case .diagnostics: return String(localized: "Diagnostics")
            case .about: return String(localized: "About")
            case .playbackSpeeds:
                return String(localized: "Playback") + " › " + String(localized: "Playback speeds")
            case .playerControls:
                return String(localized: "Playback") + " › " + String(localized: "Customize controls")
            case .subscriptionGroups:
                return String(localized: "Browsing") + " › " + String(localized: "Manage subscription groups")
            case .channelTabs:
                return String(localized: "Browsing") + " › " + String(localized: "Channel tabs")
            case .tabBar:
                return String(localized: "Appearance") + " › " + String(localized: "Tab Bar")
            case .importExport:
                return String(localized: "Library & Data") + " › " + String(localized: "Import & Export")
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
    }

    private struct Group {
        let destination: Destination
        let titles: [LocalizedStringResource]
    }

    // The visible control labels are intentionally listed here rather than extracting Form text
    // at runtime. SwiftUI views do not expose a reliable searchable control hierarchy.
    private static let groups: [Group] = [
        Group(destination: .playback, titles: [
            "Playback", "Preferred quality", "Hold for speed", "Hold speed",
            "Autoplay next video", "Allow audio from other apps",
            "Vertical swipe in fullscreen", "Show watch progress bars", "Show description",
            "Show comments", "Show featured comment preview", "Show Up Next",
            "Initial Up Next videos", "Prefetch details and comments",
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
        Group(destination: .appearance, titles: ["Appearance", "System", "Light", "Dark", "Text font"]),
        Group(destination: .tabBar, titles: ["Tab Bar", "Show tab names", "Tab order"]),
        Group(destination: .libraryData, titles: [
            "Library & Data", "Save watch history", "Add to history when opened",
            "Keep watch history", "Clear Watch History", "Continue Watching in Library",
            "Library video shelf", "Shelf content", "Shelf videos"
        ]),
        Group(destination: .importExport, titles: [
            "Import & Export", "Export All Settings and Data", "Import Full Backup",
            "Export Subscriptions CSV", "Import Subscriptions CSV", "Export Local Playlists",
            "Import Playlist Archive", "Import Playlist CSV Files"
        ]),
        Group(destination: .downloads, titles: ["Downloads", "Allow cellular data", "Parallel fragments"]),
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
