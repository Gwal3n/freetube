import Foundation
import Observation

/// Page-derived extras for the compact channel preview (latest upload + tab presence).
@available(iOS 17.0, *)
struct ChannelPreviewPageInfo: Equatable, Sendable {
    let latestTitle: String?
    let latestRelative: String?
    let hasShorts: Bool
    let hasLive: Bool

    static let empty = ChannelPreviewPageInfo(
        latestTitle: nil,
        latestRelative: nil,
        hasShorts: false,
        hasLive: false
    )

    static func from(_ details: ChannelDetails, now: Date = .now) -> ChannelPreviewPageInfo {
        let latest = details.videos.items.first
        let title = latest?.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let relative = latest?.publishedText(relativeTo: now)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? latest?.publishedRelative?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return ChannelPreviewPageInfo(
            latestTitle: title,
            latestRelative: relative,
            hasShorts: !details.shorts.items.isEmpty || details.shorts.continuationToken != nil,
            hasLive: !details.directs.items.isEmpty || details.directs.continuationToken != nil
        )
    }
}

@available(iOS 17.0, *)
@Observable
@MainActor
final class ChannelPreviewMetadataStore {
    static let shared = ChannelPreviewMetadataStore()

    private struct Entry {
        let channel: Channel?
        let pageInfo: ChannelPreviewPageInfo
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Channel?, Never>] = [:]
    private var pageInFlight: [String: Task<Void, Never>] = [:]
    private let service: any ChannelServicing
    private let pageCache: ChannelDetailsCache

    private init(
        service: any ChannelServicing = ChannelService(),
        pageCache: ChannelDetailsCache = .shared
    ) {
        self.service = service
        self.pageCache = pageCache
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

    func pageInfo(for channelID: String) -> ChannelPreviewPageInfo {
        if let entry = entries[channelID], entry.expiresAt > .now,
           entry.pageInfo != .empty {
            return entry.pageInfo
        }
        if let cached = pageCache.details(for: channelID) {
            return .from(cached)
        }
        return entries[channelID]?.pageInfo ?? .empty
    }

    func isLoading(_ channelID: String) -> Bool {
        inFlight[channelID] != nil
    }

    /// Header-only fetch for the compact preview sheet, plus a background full channel page
    /// so "Go to Channel" can paint from `ChannelDetailsCache` immediately.
    func preparePreview(for channel: Channel) async {
        prefetchChannelPage(id: channel.id)
        await loadIfNeeded(for: channel)
    }

    func loadIfNeeded(for channel: Channel) async {
        guard !channel.id.isEmpty else { return }
        guard channel.subscriberCount == nil || channel.videoCount == nil
                || channel.descriptionText?.isEmpty != false else { return }
        if let entry = entries[channel.id], entry.expiresAt > .now, entry.channel != nil { return }
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
        storeMetadata(fetched, pageInfo: nil, for: channel.id)
    }

    /// Warm the channel screen cache while the preview sheet is open.
    func prefetchChannelPage(id: String) {
        let channelID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty else { return }
        if let cached = pageCache.details(for: channelID) {
            storeMetadata(cached.channel, pageInfo: .from(cached), for: channelID)
            return
        }
        if pageInFlight[channelID] != nil { return }

        let task = Task { [service, pageCache] in
            defer { self.pageInFlight[channelID] = nil }
            do {
                let details = try await service.fetchChannel(id: channelID)
                pageCache.store(details, for: channelID)
                self.storeMetadata(details.channel, pageInfo: .from(details), for: channelID)
            } catch {
                // Preview still works from metadata; the channel screen will retry on open.
            }
        }
        pageInFlight[channelID] = task
    }

    private func storeMetadata(
        _ channel: Channel?,
        pageInfo: ChannelPreviewPageInfo?,
        for channelID: String
    ) {
        let existing = entries[channelID]
        let resolvedPage = pageInfo
            ?? existing?.pageInfo
            ?? pageCache.details(for: channelID).map(ChannelPreviewPageInfo.from)
            ?? .empty
        entries[channelID] = Entry(
            channel: channel ?? existing?.channel,
            pageInfo: resolvedPage,
            expiresAt: .now.addingTimeInterval(channel == nil ? 5 * 60 : 30 * 60)
        )
        if entries.count > 64,
           let oldestKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries.removeValue(forKey: oldestKey)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
