import Foundation
import OSLog

/// Owns recommendation paging and the playlist-specific Up Next list for one player.
/// The QueueManager remains the source of truth for ordinary Up Next items.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerRecommendationController {
    private let queue: QueueManager
    private let videoService: any VideoServicing
    private let preferences: UserPreferences
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")
    private var pager = PlayerRecommendationPager()
    @ObservationIgnored private var task: Task<Void, Never>?

    private(set) var playlistItems: [Video] = []
    private(set) var isLoadingMore = false
    var canLoadMore: Bool { pager.canLoadMore }

    init(queue: QueueManager, videoService: any VideoServicing, preferences: UserPreferences) {
        self.queue = queue
        self.videoService = videoService
        self.preferences = preferences
    }

    // MARK: - Session lifecycle

    func cancel() {
        task?.cancel()
        task = nil
    }

    func resetPager() {
        pager.reset()
        isLoadingMore = false
    }

    func clearPlaylistItems() { playlistItems = [] }

    func removeFromPlaylistItems(videoID: String) {
        playlistItems.removeAll { $0.id == videoID }
    }

    func scheduleFill(
        for seed: Video,
        isCurrent: @escaping @MainActor () -> Bool,
        isPlaylistActive: @escaping @MainActor () -> Bool,
        onDetails: @escaping @MainActor (VideoInfo) -> Void
    ) {
        cancel()
        task = Task { [weak self] in
            await self?.fill(
                for: seed, isCurrent: isCurrent,
                isPlaylistActive: isPlaylistActive, onDetails: onDetails
            )
        }
    }

    // MARK: - Paging

    func fill(
        for seed: Video,
        isCurrent: @escaping @MainActor () -> Bool,
        isPlaylistActive: @escaping @MainActor () -> Bool,
        onDetails: @escaping @MainActor (VideoInfo) -> Void
    ) async {
        let targetUpcomingCount = min(max(preferences.upNextInitialCount, 3), 15)
        let upcomingCount = isPlaylistActive()
            ? min(targetUpcomingCount, playlistItems.filter { !VideoBlocklist.shared.blocks($0) }.count)
            : min(targetUpcomingCount, queue.items.dropFirst(queue.currentIndex + 1)
                .filter { !VideoBlocklist.shared.blocks($0) }.count)
        guard upcomingCount < targetUpcomingCount else {
            log.debug("Recommendation refill skipped for \(seed.id, privacy: .public): \(upcomingCount, privacy: .public) upcoming items remain")
            return
        }

        do {
            let info = try await VideoContentPrefetchStore.shared.fetchDetails(videoID: seed.id)
            try Task.checkCancellation()
            guard isCurrent() else {
                log.debug("Discarding stale recommendations for \(seed.id, privacy: .public)")
                return
            }
            onDetails(info)
            let existingIDs = Set(queue.items.map(\.id)).union(playlistItems.map(\.id))
            let needed = targetUpcomingCount - upcomingCount
            let toAppend = pager.start(
                recommended: info.recommended,
                continuationToken: info.recommendedContinuationToken,
                excluding: existingIDs,
                limit: needed
            )
            if isPlaylistActive() {
                playlistItems = toAppend
            } else {
                queue.append(contentsOf: toAppend)
            }
            log.info("Queued \(toAppend.count, privacy: .public) recommendations for \(seed.id, privacy: .public)")
        } catch is CancellationError {
            log.debug("Recommendation fetch cancelled for \(seed.id, privacy: .public)")
        } catch {
            log.notice("Recommendation fetch failed for \(seed.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func loadMore(
        currentVideoID: @escaping @MainActor () -> String?,
        isPlaylistActive: @escaping @MainActor () -> Bool
    ) async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if let page = pager.takeBacklogPage(limit: 5) {
            if isPlaylistActive() {
                playlistItems.append(contentsOf: page)
            } else {
                queue.append(contentsOf: page)
            }
            return
        }

        guard let token = pager.continuationToken else { return }
        let videoID = currentVideoID()
        do {
            let page = try await videoService.fetchRecommendedVideos(continuation: token)
            guard !Task.isCancelled, currentVideoID() == videoID else { return }
            let existingIDs = Set(queue.items.map(\.id)).union(playlistItems.map(\.id))
            let visible = pager.accept(page, excluding: existingIDs, limit: 5)
            if isPlaylistActive() {
                playlistItems.append(contentsOf: visible)
            } else {
                queue.append(contentsOf: visible)
            }
        } catch {
            log.notice("Recommendation continuation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
