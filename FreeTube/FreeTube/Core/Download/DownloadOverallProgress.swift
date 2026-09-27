import Foundation

/// One monotonic estimate for a multi-track transfer. Phase weights reserve room for audio and
/// finalization; 100% belongs to the manager's validated `.completed` state, not a finished track.
struct DownloadOverallProgress {
    private(set) var value: Double = 0
    private var hasVideoTrack = false

    mutating func update(_ fraction: Double, phase: String) -> Double {
        let fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let estimate: Double
        switch phase {
        case "video":
            hasVideoTrack = true
            estimate = fraction * 0.80
        case "audio": estimate = hasVideoTrack ? 0.80 + fraction * 0.15 : fraction * 0.95
        case "muxing": estimate = 0.95 + fraction * 0.04
        default: estimate = fraction * 0.95
        }
        value = max(value, estimate)
        return value
    }
}
