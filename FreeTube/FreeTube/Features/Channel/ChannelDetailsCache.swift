import Foundation

@available(iOS 17.0, *)
@MainActor
final class ChannelDetailsCache {
    static let shared = ChannelDetailsCache()

    private struct Entry {
        let details: ChannelDetails
        let storedAt: Date
    }

    private let capacity: Int
    private let lifetime: TimeInterval
    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    init(capacity: Int = 20, lifetime: TimeInterval = 30 * 60) {
        self.capacity = capacity
        self.lifetime = lifetime
    }

    func details(for channelID: String, now: Date = .now) -> ChannelDetails? {
        guard UserPreferences().cacheRecentChannelContent else { return nil }
        guard let entry = entries[channelID] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < lifetime else {
            remove(channelID)
            return nil
        }
        touch(channelID)
        return entry.details
    }

    func store(_ details: ChannelDetails, for channelID: String, now: Date = .now) {
        guard UserPreferences().cacheRecentChannelContent else { return }
        entries[channelID] = Entry(details: details, storedAt: now)
        touch(channelID)
        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
    }

    func clear() {
        entries.removeAll()
        order.removeAll()
    }

    private func touch(_ channelID: String) {
        order.removeAll { $0 == channelID }
        order.append(channelID)
    }

    private func remove(_ channelID: String) {
        entries[channelID] = nil
        order.removeAll { $0 == channelID }
    }
}
