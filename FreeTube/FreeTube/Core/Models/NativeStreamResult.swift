import Foundation

/// Playback URL and ancillary metadata obtained from one native player response.
struct NativeStreamResult: Sendable {
    let url: URL
    let storyboard: VideoStoryboard?
}
