import Foundation

/// Builds the device-local feed with bounded fan-out. A failed channel never fails the entire
/// refresh and never erases that channel's last known cached videos.
final class SubscriptionFeedService: SubscriptionFeedServicing {
    private enum ChannelResult: Sendable {
        case success(channelID: String, videos: [Video])
        case failure(LocalSubscription)
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

    func refresh(subscriptions: [LocalSubscription], onProgress: @Sendable (Int, Int) async -> Void) async -> SubscriptionFeedRefresh {
        await onProgress(0, subscriptions.count)
        await writer.pruneSubscriptionFeed(validChannelIDs: Set(subscriptions.map(\.id)))
        var succeeded = 0
        var failedChannels: [LocalSubscription] = []

        // Four requests at a time is responsive without creating a burst for large CSV imports.
        for batchStart in stride(from: 0, to: subscriptions.count, by: 4) {
            guard !Task.isCancelled else { break }
            let batch = Array(subscriptions[batchStart..<min(batchStart + 4, subscriptions.count)])
            await withTaskGroup(of: ChannelResult.self) { group in
                for subscription in batch {
                    guard !Task.isCancelled else { break }
                    group.addTask { [channelService] in
                        do {
                            try Task.checkCancellation()
                            let videos = try await channelService.fetchLatestVideos(channelID: subscription.id)
                            try Task.checkCancellation()
                            return .success(
                                channelID: subscription.id,
                                videos: videos
                            )
                        } catch {
                            return .failure(subscription)
                        }
                    }
                }
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    switch result {
                    case .success(let channelID, let videos):
                        await writer.replaceSubscriptionFeedChannel(channelID: channelID, videos: videos, refreshedAt: .now)
                        succeeded += 1
                    case .failure(let subscription):
                        failedChannels.append(subscription)
                    }
                    await onProgress(succeeded + failedChannels.count, subscriptions.count)
                }
            }
        }
        return SubscriptionFeedRefresh(
            succeeded: succeeded,
            failedChannels: failedChannels.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        )
    }
}
