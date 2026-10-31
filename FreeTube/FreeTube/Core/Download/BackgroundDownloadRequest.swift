import Foundation

/// Safe to persist: video metadata and a quality choice, never a signed stream URL.
@available(iOS 17.0, *)
struct BackgroundDownloadRequest: Codable {
    let video: Video
    let qualityRawValue: String

    init(video: Video, quality: VideoQuality) {
        self.video = video
        qualityRawValue = quality.rawValue
    }

    var quality: VideoQuality { VideoQuality(rawValue: qualityRawValue) ?? .auto }
}
