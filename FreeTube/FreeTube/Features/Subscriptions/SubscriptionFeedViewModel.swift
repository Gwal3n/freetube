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
        await loadCache()
        isRefreshing = false
    }

    private func loadCache() async {
        let snapshots = await writer.fetchSubscriptionFeed()
        videos = snapshots.map(\.video)
        playbackProgress = await writer.watchProgress(videoIDs: videos.map(\.id))
    }
}
