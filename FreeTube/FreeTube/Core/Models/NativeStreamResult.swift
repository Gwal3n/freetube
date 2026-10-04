import Foundation

/// Playback URL and ancillary metadata obtained from one native player response.
struct NativeStreamResult: Sendable {
    let url: URL
    let storyboard: VideoStoryboard?
    let originalAudioLanguageCode: String?
    let originalTitle: String?
    /// Format hint for extensionless media URLs. Nil lets AVPlayer inspect the source itself.
    let mimeTypeOverride: String?

    init(url: URL, storyboard: VideoStoryboard?, originalAudioLanguageCode: String? = nil, originalTitle: String? = nil, mimeTypeOverride: String? = nil) {
        self.url = url
        self.storyboard = storyboard
        self.originalAudioLanguageCode = originalAudioLanguageCode
        self.originalTitle = originalTitle
        self.mimeTypeOverride = mimeTypeOverride
    }
}
