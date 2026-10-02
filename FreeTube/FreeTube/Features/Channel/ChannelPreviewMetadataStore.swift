import Foundation
import Observation

/// Shares short-lived channel-header lookups between native context-menu previews.
/// A preview never waits for this request before appearing; it first shows its row metadata.
@available(iOS 17.0, *)
@Observable
@MainActor
final class ChannelPreviewMetadataStore {
    static let shared = ChannelPreviewMetadataStore()

    private struct Entry {
        let channel: Channel?
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Channel?, Never>] = [:]
    private let service: any ChannelServicing

    private init(service: any ChannelServicing = ChannelService()) {
        self.service = service
    }

    func enriched(_ original: Channel) -> Channel {
        guard let entry = entries[original.id], entry.expiresAt > .now,
              let fetched = entry.channel else { return original }
        return Channel(
            id: original.id,
            name: fetched.name.isEmpty ? original.name : fetched.name,
            handle: fetched.handle ?? original.handle,
            thumbnailURL: fetched.thumbnailURL ?? original.thumbnailURL,
            bannerURL: fetched.bannerURL ?? original.bannerURL,
            subscriberCount: fetched.subscriberCount ?? original.subscriberCount,
            videoCount: fetched.videoCount ?? original.videoCount,
            isSubscribed: original.isSubscribed,
            descriptionText: fetched.descriptionText?.isEmpty == false
                ? fetched.descriptionText
                : original.descriptionText
        )
    }

    func isLoading(_ channelID: String) -> Bool {
        inFlight[channelID] != nil
    }

    func loadIfNeeded(for channel: Channel) async {
        guard !channel.id.isEmpty else { return }
        guard channel.subscriberCount == nil || channel.videoCount == nil
                || channel.descriptionText?.isEmpty != false else { return }
        if let entry = entries[channel.id], entry.expiresAt > .now { return }
        if let task = inFlight[channel.id] {
            _ = await task.value
            return
        }

        let task = Task { [service] in
            try? await service.fetchChannelMetadata(id: channel.id)
        }
        inFlight[channel.id] = task
        let fetched = await task.value
        inFlight[channel.id] = nil
        entries[channel.id] = Entry(
            channel: fetched,
            expiresAt: .now.addingTimeInterval(fetched == nil ? 5 * 60 : 30 * 60)
        )
        if entries.count > 64,
           let oldestKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries.removeValue(forKey: oldestKey)
        }
    }
}
