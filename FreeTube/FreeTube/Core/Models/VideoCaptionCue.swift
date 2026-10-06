import Foundation

/// A caption's presentation interval, measured against the selected AVPlayer item's timeline.
nonisolated struct VideoCaptionCue: Sendable, Equatable, Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let runs: [VideoCaptionRun]

    init(startTime: TimeInterval, endTime: TimeInterval, text: String, runs: [VideoCaptionRun] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.runs = runs
    }
}
