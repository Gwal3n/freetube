import Foundation

/// Session-only memory cache of recently opened channel pages. Reopening a channel shows the
/// cached page immediately while `ChannelViewModel` revalidates it in the background.
/// Holds only display metadata and continuation tokens; nothing is persisted.
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
    /// Least recently used first.
    private var order: [String] = []

    init(capacity: Int = 20, lifetime: TimeInterval = 30 * 60) {
        self.capacity = capacity
        self.lifetime = lifetime
    }

    func details(for channelID: String, now: Date = .now) -> ChannelDetails? {
        guard let entry = entries[channelID] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < lifetime else {
            remove(channelID)
            return nil
        }
        touch(channelID)
        return entry.details
    }

    func store(_ details: ChannelDetails, for channelID: String, now: Date = .now) {
        entries[channelID] = Entry(details: details, storedAt: now)
        touch(channelID)
        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
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
