import Foundation

/// Binary-plist xattr payload for a downloaded media file (URL/size come from the filesystem).
struct DownloadMetadata: Codable, Sendable {
    let videoID: String
    let title: String
    let channelName: String
    /// `"youtube"`, legacy `"ytdl"`, or `"url-fetch"`.
    let formatID: String
    let downloadedAt: Date
    let originalURL: String?
    let thumbnailData: Data?
    /// Baked at write time so list bodies never probe AVURLAsset.
    let duration: TimeInterval?
}
