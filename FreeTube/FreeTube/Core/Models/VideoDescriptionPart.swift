import Foundation

/// App-owned representation of YouTube's structured description runs. Keeping this outside the
/// networking layer lets SwiftUI render links and timestamps without importing YouTubeKit.
struct VideoDescriptionPart: Hashable, Sendable {
    enum Action: Hashable, Sendable {
        case externalURL(URL)
        case seek(TimeInterval)
        case video(String)
        case channel(String)
        case playlist(String)
    }

    let text: String
    let action: Action?
}
