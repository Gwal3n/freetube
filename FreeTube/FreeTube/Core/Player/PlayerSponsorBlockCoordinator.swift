import AVFoundation
import Foundation

/// Tracks SponsorBlock skip eligibility and AVPlayer boundary callbacks for one playback session.
/// Fetching, visible notices, chapters, and actual seeking remain with PlayerStateManager.
@MainActor
final class PlayerSponsorBlockCoordinator {
    private var boundaryObservers: [Any] = []
    private var handledSegmentIDs = Set<String>()

    func shouldObserve(
        _ segment: SponsorBlockSegment,
        behavior: SponsorBlockBehavior,
        minimumSkipSeconds: TimeInterval
    ) -> Bool {
        behavior == .autoSkip
            && !segment.isFullVideoLabel
            && segment.category != .exclusiveAccess
            && segment.category != .highlight
            && segment.category != .chapter
            && segment.endTime - segment.startTime >= max(0, minimumSkipSeconds)
    }

    func installBoundaryObservers(
        on player: AVQueuePlayer,
        for segments: [SponsorBlockSegment],
        shouldObserve: (SponsorBlockSegment) -> Bool,
        onEntry: @escaping @MainActor (SponsorBlockSegment) -> Void
    ) {
        removeBoundaryObservers(from: player)
        handledSegmentIDs.removeAll()
        for segment in segments where shouldObserve(segment) {
            let boundary = NSValue(time: CMTime(seconds: segment.startTime, preferredTimescale: 600))
            let observer = player.addBoundaryTimeObserver(forTimes: [boundary], queue: .main) {
                Task { @MainActor in onEntry(segment) }
            }
            boundaryObservers.append(observer)
        }
    }

    func markHandled(_ segmentID: String) {
        handledSegmentIDs.insert(segmentID)
    }

    /// A rewind makes every segment whose end is still ahead eligible again.
    func rearm(afterSeekingTo position: TimeInterval, segments: [SponsorBlockSegment]) {
        for segment in segments where position < segment.endTime {
            handledSegmentIDs.remove(segment.id)
        }
    }

    /// Claim the skip once and preserve the viewer's actual entry point for Undo.
    func claimSkip(
        for segment: SponsorBlockSegment,
        enteredAt currentTime: TimeInterval,
        isEnabled: Bool,
        hasVideo: Bool,
        behavior: SponsorBlockBehavior,
        minimumSkipSeconds: TimeInterval
    ) -> TimeInterval? {
        guard isEnabled,
              hasVideo,
              shouldObserve(segment, behavior: behavior, minimumSkipSeconds: minimumSkipSeconds),
              !handledSegmentIDs.contains(segment.id),
              currentTime.isFinite,
              currentTime >= segment.startTime - 0.5,
              currentTime < segment.endTime - 0.1 else { return nil }

        handledSegmentIDs.insert(segment.id)
        return currentTime <= segment.startTime + 0.75
            ? segment.startTime
            : min(currentTime, segment.endTime)
    }

    func clear(on player: AVQueuePlayer) {
        handledSegmentIDs.removeAll()
        removeBoundaryObservers(from: player)
    }

    private func removeBoundaryObservers(from player: AVQueuePlayer) {
        for observer in boundaryObservers {
            player.removeTimeObserver(observer)
        }
        boundaryObservers.removeAll()
    }
}
