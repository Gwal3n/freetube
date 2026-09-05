import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class SubscriptionFeedViewModel {
    private(set) var videos: [Video] = []
    private(set) var playbackProgress: [String: Double] = [:]
    private(set) var isRefreshing = false
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

    func load() async {
        await loadCache()
        if videos.isEmpty, hasSubscriptions { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let result = await service.refresh(subscriptions: subscriptions.subscriptions)
        failedChannelCount = result.failed
        visibleLimit = pageSize
        await loadCache()
        isRefreshing = false
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
