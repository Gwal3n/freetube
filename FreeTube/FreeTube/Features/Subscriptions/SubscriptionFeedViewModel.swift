import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class SubscriptionFeedViewModel {
    private(set) var videos: [Video] = []
    private(set) var playbackProgress: [String: Double] = [:]
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var refreshedChannels = 0
    private(set) var refreshChannelCount = 0
    private(set) var hasLoaded = false
    private(set) var failedChannelCount = 0
    private(set) var canLoadMore = false
    private(set) var lastRefreshAt: Date?
    private(set) var selectedGroupID: UUID?

    private let pageSize = 100
    private var visibleLimit = 100
    private var cacheGeneration = 0

    private let service: any SubscriptionFeedServicing
    private let writer: PersistenceWriter
    private let subscriptions: LocalSubscriptionStore
    private let groups: LocalSubscriptionGroupStore

    init(
        service: any SubscriptionFeedServicing = SubscriptionFeedService(),
        writer: PersistenceWriter = .shared,
        subscriptions: LocalSubscriptionStore = .shared,
        groups: LocalSubscriptionGroupStore = .shared
    ) {
        self.service = service
        self.writer = writer
        self.subscriptions = subscriptions
        self.groups = groups
    }

    var hasSubscriptions: Bool { !subscriptions.subscriptions.isEmpty }
    var selectedGroupName: String? {
        guard let selectedGroupID else { return nil }
        return groups.groups.first(where: { $0.id == selectedGroupID })?.name
    }

    func selectGroup(_ id: UUID?) async {
        selectedGroupID = id
        visibleLimit = pageSize
        await loadCache()
    }

    func groupsChanged() async {
        if let selectedGroupID, !groups.groups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }
        await loadCache()
    }

    var didLastRefreshCompletelyFail: Bool {
        hasLoaded
            && !isRefreshing
            && refreshChannelCount > 0
            && failedChannelCount >= refreshChannelCount
    }

    func load() async {
        await loadCache()
        hasLoaded = true
        if videos.isEmpty, hasSubscriptions { await refresh() }
    }

    /// History changes affect progress only; preserve the feed rows and pagination.
    func refreshProgress() async {
        playbackProgress = await writer.watchProgress(videoIDs: videos.map(\.id))
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshedChannels = 0
        refreshChannelCount = subscriptions.subscriptions.count
        let result = await service.refresh(subscriptions: subscriptions.subscriptions) { [weak self] completed, total in
            await self?.updateRefreshProgress(completed: completed, total: total)
        }
        failedChannelCount = result.failed
        visibleLimit = pageSize
        await loadCache()
        isRefreshing = false
    }

    private func updateRefreshProgress(completed: Int, total: Int) {
        refreshedChannels = completed
        refreshChannelCount = total
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isRefreshing else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        visibleLimit += pageSize
        await loadCache()
    }

    private func loadCache() async {
        cacheGeneration += 1
        let generation = cacheGeneration
        let channelIDs = selectedGroupID.flatMap { id in
            groups.groups.first(where: { $0.id == id })?.channelIDs
        }
        let snapshots = await writer.fetchSubscriptionFeed(limit: visibleLimit, channelIDs: channelIDs)
        let refreshedVideos = snapshots.map(\.video)
        let totalCount = await writer.subscriptionFeedCount(channelIDs: channelIDs)
        let progress = await writer.watchProgress(videoIDs: refreshedVideos.map(\.id))
        let refreshDate = await writer.latestSubscriptionFeedRefreshDate()
        guard generation == cacheGeneration else { return }
        // Commit rows and their progress together, rather than painting fresh rows with stale
        // progress while the remaining persistence reads are suspended.
        videos = refreshedVideos
        canLoadMore = refreshedVideos.count < totalCount
        playbackProgress = progress
        lastRefreshAt = refreshDate
    }
}
