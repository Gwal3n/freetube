import Foundation

/// A partially completed refresh must not make the entire subscription feed appear current.
enum FeedRefreshSchedule {
    static let retryCooldown: TimeInterval = 30 * 60

    static func isDue(
        now: Date,
        lastComplete: Date?,
        lastAttempt: Date?,
        interval: FeedRefreshInterval
    ) -> Bool {
        let completeDue = lastComplete?.addingTimeInterval(interval.seconds) ?? .distantPast
        let retryDue = lastAttempt?.addingTimeInterval(retryCooldown) ?? .distantPast
        return now >= max(completeDue, retryDue)
    }
}
