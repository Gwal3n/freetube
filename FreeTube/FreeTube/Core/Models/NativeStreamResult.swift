import Foundation

/// Playback URL and ancillary metadata obtained from one native player response.
struct NativeStreamResult: Sendable {
    let url: URL
    /// Present when `url` is video-only and a separate audio track must be played with it.
    let audioURL: URL?
    let storyboard: VideoStoryboard?
    let captionTracks: [VideoCaptionTrack]
    let originalAudioLanguageCode: String?
    let originalTitle: String?
    /// Format hint for extensionless media URLs. Nil lets AVPlayer inspect the source itself.
    let mimeTypeOverride: String?

    init(url: URL, audioURL: URL? = nil, storyboard: VideoStoryboard?, captionTracks: [VideoCaptionTrack] = [], originalAudioLanguageCode: String? = nil, originalTitle: String? = nil, mimeTypeOverride: String? = nil) {
        self.url = url
        self.audioURL = audioURL
        self.storyboard = storyboard
        self.captionTracks = captionTracks
        self.originalAudioLanguageCode = originalAudioLanguageCode
        self.originalTitle = originalTitle
        self.mimeTypeOverride = mimeTypeOverride
    }
}
