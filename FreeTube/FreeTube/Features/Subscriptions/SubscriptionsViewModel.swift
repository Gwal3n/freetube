import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class SubscriptionsViewModel {
    private(set) var feedVideos: [Video] = []
    private(set) var channels: [Channel] = []
    private(set) var isLoading: Bool = false
    var errorState: ErrorState?

    private let service: any SubscriptionServicing

    init(service: any SubscriptionServicing = SubscriptionService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let feed = service.fetchFeed()
        async let subs = service.fetchSubscriptions()
        do {
            let result = try await feed
            feedVideos = result.videos
            channels = try await subs
        } catch {
            errorState = ErrorState(from: error)
        }
    }

}
