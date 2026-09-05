import Foundation

/// One-shot navigation request routed to whichever tab is currently visible. Each tab owns its
/// own `NavigationStack`, so opening a channel or playlist never moves the user into Search.
struct AppNavigationRequest: Identifiable, Equatable {
    enum Destination: Hashable {
        case channel(String)
        case playlist(String)
        case localPlaylist(String)
    }

    let id = UUID()
    let destination: Destination
}
