import Foundation

/// Lightweight Library route owned by the app-level navigation host, not by TabView content.
enum LibraryNavigationDestination: String, Hashable {
    case history
    case subscriptions
    case playlists
    case probe
}

extension Notification.Name {
    static let freetubeOpenLibraryDestination = Notification.Name("com.leshko.freetube.openLibraryDestination")
}
