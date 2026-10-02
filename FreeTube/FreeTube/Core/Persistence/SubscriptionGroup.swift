import Foundation

/// A device-local collection of subscribed channels. A channel may belong to several groups.
struct SubscriptionGroup: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var channelIDs: Set<String>
}
