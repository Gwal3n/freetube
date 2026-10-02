import Foundation

/// Durable playlist membership and job state. Media remains in the existing per-video files;
/// this record only preserves their order and the user's intent to keep them as a playlist.
struct PlaylistDownloadManifest: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable, Equatable {
        case queued
        case preparing
        case downloading
        case paused
        case finished
    }

    let id: String
    var title: String
    var thumbnailURL: URL?
    var videos: [Video]
    var continuationToken: String?
    var qualityRawValue: String
    var failedVideoIDs: Set<String>
    var status: Status
    var createdAt: Date
    var updatedAt: Date
    var lastError: String?

    var quality: VideoQuality { VideoQuality(rawValue: qualityRawValue) ?? .auto }

    var isPrepared: Bool { continuationToken == nil }
}
