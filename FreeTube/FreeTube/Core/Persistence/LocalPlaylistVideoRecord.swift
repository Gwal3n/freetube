import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class LocalPlaylistVideoRecord {
    @Attribute(.unique) var membershipID: String
    var playlistID: String
    var videoID: String
    var title: String
    var channelID: String
    var channelName: String
    var channelThumbnailURL: URL?
    var thumbnailURL: URL?
    var duration: TimeInterval?
    var viewCount: Int?
    var publishedAt: Date?
    var publishedRelative: String?
    var descriptionSnippet: String?
    var isLive: Bool
    var isShort: Bool
    var position: Int
    var addedAt: Date
    /// 0 = ordinary/resolved, 1 = waiting for imported metadata, 2 = resolution failed.
    var metadataState: Int = 0

    init(
        playlistID: String,
        video: Video,
        position: Int,
        addedAt: Date = .now,
        metadataState: Int = 0
    ) {
        membershipID = "\(playlistID):\(video.id)"
        self.playlistID = playlistID
        videoID = video.id
        title = video.title
        channelID = video.channelID
        channelName = video.channelName
        channelThumbnailURL = video.channelThumbnailURL
        thumbnailURL = video.thumbnailURL
        duration = video.duration
        viewCount = video.viewCount
        publishedAt = video.publishedAt
        publishedRelative = video.publishedRelative
        descriptionSnippet = video.descriptionSnippet
        isLive = video.isLive
        isShort = video.isShort
        self.position = position
        self.addedAt = addedAt
        self.metadataState = metadataState
    }
}
