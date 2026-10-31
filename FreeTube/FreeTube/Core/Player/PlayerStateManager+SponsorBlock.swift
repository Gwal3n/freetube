import AVFoundation
import Foundation
import OSLog

/// SponsorBlock commands and chapter presentation for the shared player.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Notice commands

    func undoSponsorBlockSkip() {
        guard let notice = sponsorBlockNotice else { return }
        sponsorBlockCoordinator.dismissNotice()
        // Undo is the one rewind that should not immediately trigger the same skip again.
        seek(to: notice.originalStartTime, rearmSponsorBlock: false)
    }

    func confirmSponsorBlockSkip() {
        guard let notice = sponsorBlockNotice,
              case .prompt(let endTime) = notice.kind else { return }
        sponsorBlockCoordinator.dismissNotice()
        seek(to: endTime)
    }

    func dismissSponsorBlockNotice() {
        sponsorBlockCoordinator.dismissNotice()
    }

    // MARK: - Segment lifecycle

    func loadSponsorBlockSegments(for videoID: String) {
        guard preferences.sponsorBlockEnabled else { return }
        let categories = preferences.sponsorBlockCategories
        guard !categories.isEmpty else { return }
        sponsorBlockCoordinator.loadSegments(
            for: videoID,
            categories: categories,
            isCurrent: { [weak self] in self?.currentVideo?.id == videoID },
            onLoaded: { [weak self] segments in
                self?.installSponsorBlockObservers(for: segments)
            }
        )
    }

    private func installSponsorBlockObservers(for segments: [SponsorBlockSegment]) {
        let installation = sponsorBlockCoordinator.installSegments(
            segments,
            on: player,
            elapsed: elapsed,
            preferences: preferences,
            onEntry: { [weak self] in self?.handleSponsorBlockSegment($0) }
        )
        updateDisplayedChapters()

        // A highlight is a point to jump *to*, not a duration to skip once playback reaches it.
        // Offer it as soon as the lookup finishes while leaving Show only as a marker-only mode.
        if let highlight = installation.highlight {
            showSponsorBlockNotice(SponsorBlockNotice(
                category: .highlight,
                originalStartTime: elapsed,
                kind: .prompt(endTime: highlight.startTime)
            ))
        }

        // The lookup may finish after playback has already entered a segment. Boundary observers
        // cannot fire retroactively, so evaluate the current position once immediately.
        if let current = installation.current {
            handleSponsorBlockSegment(current, enteredAt: elapsed)
        }
    }

    private func shouldObserveSponsorBlockSegment(_ segment: SponsorBlockSegment) -> Bool {
        sponsorBlockCoordinator.shouldObserve(
            segment,
            behavior: preferences.sponsorBlockBehavior(for: segment.category),
            minimumSkipSeconds: preferences.sponsorBlockMinimumSkipSeconds
        )
    }

    func handleSponsorBlockSegment(at time: TimeInterval) {
        guard let segment = sponsorBlockSegments.first(where: {
            shouldObserveSponsorBlockSegment($0)
                && time >= $0.startTime - 0.5
                && time < $0.endTime - 0.1
        }) else { return }
        handleSponsorBlockSegment(segment, enteredAt: time)
    }

    private func handleSponsorBlockSegment(
        _ segment: SponsorBlockSegment,
        enteredAt explicitEntryTime: TimeInterval? = nil
    ) {
        let currentTime = explicitEntryTime ?? player.currentTime().seconds
        // Preserve where the viewer actually entered the segment. A boundary observer can fire a
        // fraction late during ordinary playback, so positions near the beginning normalize to
        // the true segment start. A manual scrub into the middle retains its settled seek target.
        guard let undoPosition = sponsorBlockCoordinator.claimSkip(
            for: segment,
            enteredAt: currentTime,
            isEnabled: preferences.sponsorBlockEnabled,
            hasVideo: currentVideo != nil,
            behavior: preferences.sponsorBlockBehavior(for: segment.category),
            minimumSkipSeconds: preferences.sponsorBlockMinimumSkipSeconds
        ) else { return }
        sponsorBlockCoordinator.cancelNoticeDismissal()

        log.info("SponsorBlock skipping category=\(segment.category.rawValue, privacy: .public) duration=\(segment.endTime - segment.startTime, privacy: .public)s")
        seek(to: segment.endTime)
        showSponsorBlockNotice(SponsorBlockNotice(
            category: segment.category,
            originalStartTime: undoPosition,
            kind: .skipped
        ))
    }

    private func showSponsorBlockNotice(_ notice: SponsorBlockNotice) {
        let seconds = min(max(preferences.sponsorBlockNoticeSeconds, 1), 15)
        sponsorBlockCoordinator.showNotice(notice, for: seconds)
    }

    /// Clears cached segment responses without changing the currently playing video's markers.
    func clearSponsorBlockCache() {
        sponsorBlockCoordinator.clearCache()
    }

    func clearSponsorBlockState() {
        sponsorBlockCoordinator.clear(on: player)
    }

    // MARK: - Chapters

    func clearChapterState() {
        youtubeChapters = []
        sponsorBlockCoordinator.clearCommunityChapters()
        chapters = []
    }

    func updateDisplayedChapters() {
        // Community chapters are a separate optional source. If none were submitted, retain
        // YouTube chapters; neither source is mixed with the other or used for automatic seeks.
        let communityChapters = sponsorBlockCoordinator.communityChapters
        chapters = communityChapters.isEmpty ? youtubeChapters : communityChapters
    }

}
