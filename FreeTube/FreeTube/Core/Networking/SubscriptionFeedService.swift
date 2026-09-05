import Foundation

/// Builds the device-local feed with bounded fan-out. A failed channel never fails the entire
/// refresh and never erases that channel's last known cached videos.
final class SubscriptionFeedService: SubscriptionFeedServicing {
    private enum ChannelResult: Sendable {
        case success(channelID: String, videos: [Video])
        case failure
    }
    private let channelService: any ChannelServicing
    private let writer: PersistenceWriter

    init(
        channelService: any ChannelServicing = ChannelService(),
        writer: PersistenceWriter = .shared
    ) {
        self.channelService = channelService
        self.writer = writer
    }

    func refresh(subscriptions: [LocalSubscription]) async -> SubscriptionFeedRefresh {
        await writer.pruneSubscriptionFeed(validChannelIDs: Set(subscriptions.map(\.id)))
        var succeeded = 0
        var failed = 0

        // Four requests at a time is responsive without creating a burst for large CSV imports.
        for batchStart in stride(from: 0, to: subscriptions.count, by: 4) {
            let batch = Array(subscriptions[batchStart..<min(batchStart + 4, subscriptions.count)])
            await withTaskGroup(of: ChannelResult.self) { group in
                for subscription in batch {
                    group.addTask { [channelService] in
                        do {
                            return .success(
                                channelID: subscription.id,
                                videos: try await channelService.fetchLatestVideos(channelID: subscription.id)
                            )
                        } catch {
                            return .failure
                        }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let channelID, let videos):
                        await writer.replaceSubscriptionFeedChannel(channelID: channelID, videos: videos, refreshedAt: .now)
                        succeeded += 1
                    case .failure:
                        failed += 1
                    }
                }
            }
        }
        return SubscriptionFeedRefresh(succeeded: succeeded, failed: failed)
    }
}
