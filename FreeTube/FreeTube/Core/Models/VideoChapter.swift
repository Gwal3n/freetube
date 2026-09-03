import Foundation

/// App-owned chapter metadata. The UI never depends directly on YouTubeKit's response types.
struct VideoChapter: Identifiable, Hashable, Sendable {
    let title: String
    let startTime: TimeInterval
    let timeDescription: String?
    let thumbnailURL: URL?

    var id: TimeInterval { startTime }
}
