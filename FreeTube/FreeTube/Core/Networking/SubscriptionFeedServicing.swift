protocol SubscriptionFeedServicing: Sendable {
    func refresh(subscriptions: [LocalSubscription]) async -> SubscriptionFeedRefresh
}
