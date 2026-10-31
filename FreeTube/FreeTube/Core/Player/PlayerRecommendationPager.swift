import Foundation

/// Keeps the unseen recommendation pages for the current video in memory. The player decides
/// whether returned videos belong in its queue or in the active playlist's Up Next section.
@available(iOS 17.0, *)
@MainActor
struct PlayerRecommendationPager {
    private var backlog: [Video] = []
    private(set) var continuationToken: String?

    var canLoadMore: Bool { !backlog.isEmpty || continuationToken != nil }

    mutating func reset() {
        backlog.removeAll()
        continuationToken = nil
    }

    /// Accept the watch page's initial recommendations and retain the remainder for later pages.
    mutating func start(
        recommended: [Video],
        continuationToken: String?,
        excluding existingIDs: Set<String>,
        limit: Int
    ) -> [Video] {
        let fresh = recommended.filter {
            !existingIDs.contains($0.id) && !VideoBlocklist.shared.blocks($0)
        }
        let visible = Array(fresh.prefix(limit))
        backlog = Array(fresh.dropFirst(visible.count))
        self.continuationToken = continuationToken
        return visible
    }

    /// Return nil when the in-memory backlog is exhausted so the caller can fetch a continuation.
    mutating func takeBacklogPage(limit: Int) -> [Video]? {
        backlog.removeAll { VideoBlocklist.shared.blocks($0) }
        guard !backlog.isEmpty else { return nil }
        let visible = Array(backlog.prefix(limit))
        backlog.removeFirst(visible.count)
        return visible
    }

    /// Keep later continuation items after returning a small page to Up Next.
    mutating func accept(
        _ page: RecommendedVideosPage,
        excluding existingIDs: Set<String>,
        limit: Int
    ) -> [Video] {
        let fresh = page.videos.filter {
            !existingIDs.contains($0.id) && !VideoBlocklist.shared.blocks($0)
        }
        let visible = Array(fresh.prefix(limit))
        backlog = Array(fresh.dropFirst(visible.count))
        continuationToken = page.continuationToken
        return visible
    }
}
