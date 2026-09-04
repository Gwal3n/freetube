import Foundation
import OSLog
import YouTubeKit

struct SubscriptionFeed: Sendable {
    let videos: [Video]
    let continuationToken: String?
}

struct SubscriptionsPage: Sendable {
    let channels: [Channel]
    let continuationToken: String?
}

protocol SubscriptionServicing: Sendable {
    func fetchFeed() async throws -> SubscriptionFeed
    func fetchSubscriptions() async throws -> [Channel]
    func fetchSubscriptionsPage() async throws -> SubscriptionsPage
    func fetchSubscriptionsMore(continuation: String) async throws -> SubscriptionsPage
}

/// Read-only access to the signed-in account's subscription pages. Subscription changes in this
/// app are device-only and are handled by `LocalSubscriptionStore`.
final class SubscriptionService: SubscriptionServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SubscriptionService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    func fetchFeed() async throws -> SubscriptionFeed {
        log.info("Fetching subscriptions feed")
        throw YouTubeServiceError.notAuthenticated
    }

    func fetchSubscriptions() async throws -> [Channel] {
        try await fetchSubscriptionsPage().channels
    }

    /// First page of the user's subscribed channels. Uses `AccountSubscriptionsResponse`, which
    /// returns up to ~30 channels per page plus a continuation token for the next batch.
    func fetchSubscriptionsPage() async throws -> SubscriptionsPage {
        log.info("[subs] fetchSubscriptionsPage")
        do {
            let response = try await AccountSubscriptionsResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [:]
            )
            if response.isDisconnected {
                log.notice("[subs] fetchSubscriptionsPage: response isDisconnected=true")
                throw YouTubeServiceError.notAuthenticated
            }
            let channels = response.results.map(Mappers.channel(from:))
            log.info("[subs] fetchSubscriptionsPage: \(channels.count, privacy: .public) channels, more=\(response.continuationToken != nil, privacy: .public)")
            return SubscriptionsPage(channels: channels, continuationToken: response.continuationToken)
        } catch let error as YouTubeServiceError {
            throw error
        } catch {
            log.error("[subs] fetchSubscriptionsPage failed: \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchSubscriptionsMore(continuation: String) async throws -> SubscriptionsPage {
        log.info("[subs] fetchSubscriptionsMore")
        do {
            let response = try await AccountSubscriptionsResponse.Continuation.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.continuation: continuation]
            )
            if response.isDisconnected {
                throw YouTubeServiceError.notAuthenticated
            }
            let channels = response.results.map(Mappers.channel(from:))
            return SubscriptionsPage(channels: channels, continuationToken: response.continuationToken)
        } catch let error as YouTubeServiceError {
            throw error
        } catch {
            log.error("[subs] fetchSubscriptionsMore failed: \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.network(error)
        }
    }

}
