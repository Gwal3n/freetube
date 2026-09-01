import Foundation

enum PlaybackSource: Sendable, Hashable {
    case direct(URL)
    case localFile(URL)
    /// Separate video-only + audio-only streams that the player must stitch together via
    /// `AVMutableComposition`. This is how YouTube delivers most non-music VOD on the iOS-client
    /// endpoint — combined "progressive" formats and HLS manifests are reserved for a small subset.
    case composite(video: URL, audio: URL)

    var url: URL {
        switch self {
        case .direct(let url): return url
        case .localFile(let url): return url
        case .composite(let video, _): return video
        }
    }
}

/// Identifies the resolver that produced a candidate without exposing its signed URL.
enum PlaybackStrategy: String, Sendable, Hashable {
    case localFile = "local-file"
    case b5iIOS = "b5i-ios"
    case b5iTVHTML5 = "b5i-tvhtml5"
    case native = "native-youtubekit"
    case legacyDownload = "legacy-download"
}

struct PlaybackCandidate: Sendable, Hashable {
    let source: PlaybackSource
    let strategy: PlaybackStrategy
}

protocol PlaybackResolving {
    /// Returns the next usable candidate. A URL is only considered proven after AVPlayer reports
    /// `.readyToPlay`; callers exclude rejected strategies and ask again for the fallback.
    func resolve(
        video: Video,
        quality: VideoQuality,
        excluding strategies: Set<PlaybackStrategy>
    ) async throws -> PlaybackCandidate
}
