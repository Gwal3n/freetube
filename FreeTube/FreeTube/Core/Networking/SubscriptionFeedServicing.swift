protocol SubscriptionFeedServicing: Sendable {
    func refresh(subscriptions: [LocalSubscription], onProgress: @Sendable (Int, Int) async -> Void) async -> SubscriptionFeedRefresh
    func refreshViewCounts(channelIDs: [String]) async -> [String: Int]
}
