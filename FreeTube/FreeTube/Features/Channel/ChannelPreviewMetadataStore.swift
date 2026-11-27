import Foundation
import Observation

/// Page-derived extras for the compact channel preview's latest-upload row.
@available(iOS 17.0, *)
struct ChannelPreviewPageInfo: Equatable, Sendable {
    let latestTitle: String?
    let latestRelative: String?
    let latestViewCount: Int?
    /// Absolute or reconstructed upload time for the latest video; drives the 12-month cutoff.
    let latestPublishedAt: Date?

    static let empty = ChannelPreviewPageInfo(
        latestTitle: nil,
        latestRelative: nil,
        latestViewCount: nil,
        latestPublishedAt: nil
    )

    /// Recent enough to show the video title in the compact preview.
    var showsLatestTitle: Bool {
        guard let latestPublishedAt else {
            return Self.relativeSuggestsUnderOneYear(latestRelative)
        }
        return Date.now.timeIntervalSince(latestPublishedAt) < Self.oneYear
    }

    private static let oneYear: TimeInterval = 365.25 * 24 * 60 * 60

    static func from(_ details: ChannelDetails, now: Date = .now) -> ChannelPreviewPageInfo {
        let latest = details.videos.items.first
        return ChannelPreviewPageInfo(
            latestTitle: Self.nonEmpty(latest?.title),
            latestRelative: Self.relativeAge(for: latest, now: now),
            latestViewCount: latest?.viewCount,
            latestPublishedAt: latest?.estimatedPublishedAt(relativeTo: now)
        )
    }

    private static func relativeSuggestsUnderOneYear(_ relative: String?) -> Bool {
        guard let text = relative?.lowercased(), !text.isEmpty else { return false }
        if text.contains("year") { return false }
        return text.contains("second")
            || text.contains("minute")
            || text.contains("hour")
            || text.contains("day")
            || text.contains("week")
            || text.contains("month")
    }

    private static func relativeAge(for video: Video?, now: Date) -> String? {
        guard let video else { return nil }
        if let text = nonEmpty(video.publishedText(relativeTo: now)) {
            return text
        }
        return nonEmpty(video.publishedRelative)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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
            return ChannelPreviewPageInfo.from(cached)
        }
        return entries[channelID]?.pageInfo ?? .empty
    }

    func isLoading(_ channelID: String) -> Bool {
        inFlight[channelID] != nil
    }

    /// Header-only fetch for the compact preview sheet, plus a background full channel page
    /// so opening the channel can paint from `ChannelDetailsCache` immediately.
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
            storeMetadata(cached.channel, pageInfo: ChannelPreviewPageInfo.from(cached), for: channelID)
            return
        }
        if pageInFlight[channelID] != nil { return }

        let task = Task { [service, pageCache] in
            defer { self.pageInFlight[channelID] = nil }
            do {
                let details = try await service.fetchChannel(id: channelID)
                pageCache.store(details, for: channelID)
                self.storeMetadata(
                    details.channel,
                    pageInfo: ChannelPreviewPageInfo.from(details),
                    for: channelID
                )
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
        let resolvedPage: ChannelPreviewPageInfo
        if let pageInfo {
            resolvedPage = pageInfo
        } else if let existingPage = existing?.pageInfo, existingPage != .empty {
            resolvedPage = existingPage
        } else if let cached = pageCache.details(for: channelID) {
            resolvedPage = ChannelPreviewPageInfo.from(cached)
        } else {
            resolvedPage = existing?.pageInfo ?? .empty
        }
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
