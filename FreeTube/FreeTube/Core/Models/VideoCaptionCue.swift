import Foundation

/// A caption's presentation interval, measured against the selected AVPlayer item's timeline.
struct VideoCaptionCue: Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}
