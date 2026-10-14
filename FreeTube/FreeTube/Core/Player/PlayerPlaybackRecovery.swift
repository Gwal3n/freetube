import Foundation

/// Immutable context carried into the one permitted post-start resolver retry.
/// For live streams, `position` is the distance behind the live edge, not absolute time.
struct PlayerPlaybackRecovery: Sendable {
    let sessionID: Int
    let failedStrategy: PlaybackStrategy?
    let position: TimeInterval
    let isLive: Bool
    let resumeFromHistoryIfUnstarted: Bool

    init(
        sessionID: Int,
        failedStrategy: PlaybackStrategy?,
        currentTime: TimeInterval,
        elapsed: TimeInterval,
        liveSeekableRange: ClosedRange<TimeInterval>?,
        isLive: Bool,
        resumeFromHistoryIfUnstarted: Bool
    ) {
        let currentPosition = currentTime.isFinite && currentTime >= 0 ? currentTime : elapsed
        let behindLiveEdge = liveSeekableRange.map { max(0, $0.upperBound - currentPosition) } ?? 0
        self.sessionID = sessionID
        self.failedStrategy = failedStrategy
        position = isLive ? behindLiveEdge : max(0, currentPosition)
        self.isLive = isLive
        self.resumeFromHistoryIfUnstarted = resumeFromHistoryIfUnstarted
            && !isLive && currentPosition < 1
    }

    /// Nil means seek to the newest live edge. Use the newest contiguous range, not a span
    /// across disjoint seekable windows.
    func liveSeekTarget(in ranges: [ClosedRange<TimeInterval>]) -> TimeInterval? {
        guard let newest = ranges.max(by: { $0.upperBound < $1.upperBound }), position > 5 else {
            return nil
        }
        return min(newest.upperBound, max(newest.lowerBound, newest.upperBound - position))
    }
}
