import AVFoundation
import Foundation
import OSLog

/// Owns SponsorBlock lookup, skip eligibility, boundary observers, and visible notices.
/// PlayerStateManager performs the actual seek when a segment is claimed.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerSponsorBlockCoordinator {
    private let service: any SponsorBlockServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")
    @ObservationIgnored private var boundaryObservers: [Any] = []
    @ObservationIgnored private var handledSegmentIDs = Set<String>()
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    private(set) var segments: [SponsorBlockSegment] = []
    private(set) var notice: SponsorBlockNotice?
    private(set) var communityChapters: [VideoChapter] = []

    init(service: any SponsorBlockServicing = SponsorBlockService()) {
        self.service = service
    }

    // MARK: - Lookup and presentation timing

    func loadSegments(
        for videoID: String,
        categories: Set<SponsorBlockCategory>,
        isCurrent: @escaping @MainActor () -> Bool,
        onLoaded: @escaping @MainActor ([SponsorBlockSegment]) -> Void
    ) {
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let segments = try await service.fetchSegments(videoID: videoID, categories: categories)
                try Task.checkCancellation()
                guard isCurrent() else { return }
                onLoaded(segments)
                let fullLabels = segments.filter(\.isFullVideoLabel).count
                log.info("SponsorBlock loaded \(segments.count, privacy: .public) segments (full labels=\(fullLabels, privacy: .public)) for \(videoID, privacy: .public)")
            } catch is CancellationError {
                log.debug("SponsorBlock lookup cancelled for \(videoID, privacy: .public)")
            } catch {
                // Lookup failures are optional metadata failures, never playback failures.
                log.notice("SponsorBlock lookup failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Install skip boundaries and return the chapter/notice candidates for the current playhead.
    func installSegments(
        _ segments: [SponsorBlockSegment],
        on player: AVQueuePlayer,
        elapsed: TimeInterval,
        preferences: UserPreferences,
        onEntry: @escaping @MainActor (SponsorBlockSegment) -> Void
    ) -> (highlight: SponsorBlockSegment?, current: SponsorBlockSegment?) {
        self.segments = segments
        var chapterStarts = Set<TimeInterval>()
        communityChapters = segments.compactMap { segment -> VideoChapter? in
            guard segment.category == .chapter,
                  let title = segment.title,
                  chapterStarts.insert(segment.startTime).inserted else { return nil }
            return VideoChapter(
                title: title, startTime: segment.startTime,
                timeDescription: nil, thumbnailURL: nil
            )
        }
        let isSkippable: (SponsorBlockSegment) -> Bool = { segment in
            self.shouldObserve(
                segment,
                behavior: preferences.sponsorBlockBehavior(for: segment.category),
                minimumSkipSeconds: preferences.sponsorBlockMinimumSkipSeconds
            )
        }
        installBoundaryObservers(on: player, for: segments, shouldObserve: isSkippable, onEntry: onEntry)
        let highlight = segments.first {
            $0.category == .highlight
                && preferences.sponsorBlockBehavior(for: $0.category) == .ask
                && elapsed < $0.startTime - 0.5
        }
        if let highlight { markHandled(highlight.id) }
        let current = segments.first {
            isSkippable($0) && elapsed >= $0.startTime && elapsed < $0.endTime
        }
        return (highlight, current)
    }

    func showNotice(_ notice: SponsorBlockNotice, for seconds: TimeInterval) {
        noticeTask?.cancel()
        self.notice = notice
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard self?.notice?.id == notice.id else { return }
            self?.notice = nil
        }
    }

    func cancelNoticeDismissal() {
        noticeTask?.cancel()
        noticeTask = nil
    }

    func dismissNotice() {
        cancelNoticeDismissal()
        notice = nil
    }

    func clearCommunityChapters() { communityChapters = [] }

    func clearCache() { service.clearCache() }

    // MARK: - Skip boundaries

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
        lookupTask?.cancel()
        lookupTask = nil
        dismissNotice()
        segments = []
        communityChapters = []
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
