import Foundation

/// Shared secondary text for compact and large video rows. Missing values are omitted before
/// separators are joined, and a supplied date keeps relative upload text current in a feed.
enum VideoMetadataLine {
    static func details(for video: Video, relativeTo reference: Date?) -> String {
        let published = reference.flatMap { video.publishedText(relativeTo: $0) }
            ?? video.publishedRelative ?? ""
        return [video.viewCountString, published]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    static func withChannel(for video: Video, relativeTo reference: Date?) -> String {
        [video.channelName, details(for: video, relativeTo: reference)]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
