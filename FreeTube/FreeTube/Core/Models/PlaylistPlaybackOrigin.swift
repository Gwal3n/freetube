import Foundation

/// Identifies where an active playlist came from so History can reopen the same collection.
nonisolated enum PlaylistPlaybackOrigin: String, Codable, Sendable {
    case youtube
    case local
    case downloaded
}
