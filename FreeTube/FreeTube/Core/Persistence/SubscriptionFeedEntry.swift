import Foundation
import SwiftData

/// Persisted, dependency-free snapshot of a subscription-feed row. Stream URLs are never stored.
@available(iOS 17.0, *)
@Model
final class SubscriptionFeedEntry {
    @Attribute(.unique) var videoID: String
    var title: String
    var channelID: String
    var channelName: String
    var channelThumbnailURL: URL?
    var thumbnailURL: URL?
    var duration: TimeInterval?
    var viewCount: Int?
    var publishedRelative: String?
    var sortDate: Date
    var refreshedAt: Date
    var isLive: Bool

    init(video: Video, sortDate: Date, refreshedAt: Date) {
        videoID = video.id
        title = video.title
        channelID = video.channelID
        channelName = video.channelName
        channelThumbnailURL = video.channelThumbnailURL
        thumbnailURL = video.thumbnailURL
        duration = video.duration
        viewCount = video.viewCount
        publishedRelative = video.publishedRelative
        self.sortDate = sortDate
        self.refreshedAt = refreshedAt
        isLive = video.isLive
    }
}
