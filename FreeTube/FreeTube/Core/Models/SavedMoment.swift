import Foundation

/// A deliberate, device-local timestamp bookmark. Only public video metadata is stored; signed
/// playback URLs and caption-track URLs never enter this record or an exported backup.
struct SavedMoment: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let video: Video
    let time: TimeInterval
    var label: String?
    let savedAt: Date

    var timestampText: String {
        let total = Int(min(max(0, time), Double(Int32.max)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
