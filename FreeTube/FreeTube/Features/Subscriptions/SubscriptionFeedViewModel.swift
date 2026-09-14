import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class SubscriptionFeedViewModel {
    private(set) var videos: [Video] = []
    private(set) var playbackProgress: [String: Double] = [:]
    private(set) var isRefreshing = false
    private(set) var refreshedChannels = 0
    private(set) var refreshChannelCount = 0
    private(set) var hasLoaded = false
    private(set) var failedChannelCount = 0
    private(set) var canLoadMore = false

    private let pageSize = 100
    private var visibleLimit = 100

    private let service: any SubscriptionFeedServicing
    private let writer: PersistenceWriter
    private let subscriptions: LocalSubscriptionStore

    init(
        service: any SubscriptionFeedServicing = SubscriptionFeedService(),
        writer: PersistenceWriter = .shared,
        subscriptions: LocalSubscriptionStore = .shared
    ) {
        self.service = service
        self.writer = writer
        self.subscriptions = subscriptions
    }

    var hasSubscriptions: Bool { !subscriptions.subscriptions.isEmpty }

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
        guard canLoadMore else { return }
        visibleLimit += pageSize
        await loadCache()
    }

    private func loadCache() async {
        let snapshots = await writer.fetchSubscriptionFeed(limit: visibleLimit)
        videos = snapshots.map(\.video)
        let totalCount = await writer.subscriptionFeedCount()
        canLoadMore = videos.count < totalCount
        playbackProgress = await writer.watchProgress(videoIDs: videos.map(\.id))
    }
}
