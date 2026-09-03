import Foundation

/// A single timed caption cue ready for the player overlay.
struct CaptionCue: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    func contains(_ time: TimeInterval) -> Bool {
        startTime <= time && time < endTime
    }
}
