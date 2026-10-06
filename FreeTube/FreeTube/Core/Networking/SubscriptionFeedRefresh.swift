struct SubscriptionFeedRefresh: Sendable {
    let succeeded: Int
    let failedChannels: [LocalSubscription]
}
