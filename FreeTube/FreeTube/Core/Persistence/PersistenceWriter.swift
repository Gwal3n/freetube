import Foundation
import SwiftData

/// Background actor for every SwiftData write the app performs.
///
/// **Why an actor:** SwiftData `ModelContext` is not thread-safe — it must only be used from the
/// thread/actor that created it. The `@ModelActor` macro generates an initializer that constructs
/// a context bound to this actor's isolated executor, so all writes happen on a single dedicated
/// background queue and never block the main thread. `@Query` views observing the main context
/// still pick up changes automatically once `save()` lands (SwiftData propagates persistent-store
/// notifications back to the main context).
///
/// **What's serialized here:** WatchHistory, FavoriteVideo, SearchHistory, and the local
/// subscription-feed cache. (Downloads
/// moved to file-system + xattr storage in `DownloadsStore` — no SwiftData involved.)
/// Reads (favorite lookup, recent history, etc.) still go through SwiftUI `@Query` or the main
/// context — those are reactive and indexed.
@available(iOS 17.0, *)
@ModelActor
actor PersistenceWriter {
    static let shared = PersistenceWriter(modelContainer: PersistenceController.sharedContainer)

    // MARK: - Subscription feed

    func fetchSubscriptionFeed() -> [SubscriptionFeedSnapshot] {
        let descriptor = FetchDescriptor<SubscriptionFeedEntry>(
            sortBy: [SortDescriptor(\SubscriptionFeedEntry.sortDate, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map { entry in
            SubscriptionFeedSnapshot(
                video: Video(
                    id: entry.videoID,
                    title: entry.title,
                    channelID: entry.channelID,
                    channelName: entry.channelName,
                    channelThumbnailURL: entry.channelThumbnailURL,
                    thumbnailURL: entry.thumbnailURL,
                    duration: entry.duration,
                    viewCount: entry.viewCount,
                    publishedAt: nil,
                    publishedRelative: entry.publishedRelative,
                    descriptionSnippet: nil,
                    isLive: entry.isLive,
                    isShort: false
                ),
                sortDate: entry.sortDate
            )
        }
    }

    /// Replaces only one successfully refreshed channel. Failed channels consequently retain
    /// their last good rows, while a successful empty response correctly clears stale entries.
    func replaceSubscriptionFeedChannel(channelID: String, videos: [Video], refreshedAt: Date) {
        let target = channelID
        let descriptor = FetchDescriptor<SubscriptionFeedEntry>(predicate: #Predicate { $0.channelID == target })
        for entry in (try? modelContext.fetch(descriptor)) ?? [] { modelContext.delete(entry) }
        for (index, video) in videos.enumerated() {
            modelContext.insert(SubscriptionFeedEntry(
                video: video,
                sortDate: Self.estimatedPublishDate(video.publishedRelative, fallback: refreshedAt.addingTimeInterval(-Double(index))),
                refreshedAt: refreshedAt
            ))
        }
        try? modelContext.save()
    }

    func pruneSubscriptionFeed(validChannelIDs: Set<String>) {
        let descriptor = FetchDescriptor<SubscriptionFeedEntry>()
        for entry in (try? modelContext.fetch(descriptor)) ?? [] where !validChannelIDs.contains(entry.channelID) {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    private static func estimatedPublishDate(_ text: String?, fallback: Date) -> Date {
        guard let text = text?.lowercased() else { return fallback }
        let value = Int(text.split(separator: " ").first ?? "") ?? 0
        let interval: TimeInterval
        if text.contains("minute") { interval = Double(value) * 60 }
        else if text.contains("hour") { interval = Double(value) * 3_600 }
        else if text.contains("day") { interval = Double(value) * 86_400 }
        else if text.contains("week") { interval = Double(value) * 604_800 }
        else if text.contains("month") { interval = Double(value) * 2_629_746 }
        else if text.contains("year") { interval = Double(value) * 31_556_952 }
        else { return fallback }
        return fallback.addingTimeInterval(-interval)
    }

    // MARK: - WatchHistoryEntry

    /// Bump `watchedAt` on a play, or insert a new row. One indexed-column fetch + one write.
    func upsertWatchHistory(
        videoID: String,
        title: String,
        channelName: String,
        thumbnailURL: URL?,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        let target = videoID
        let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.watchedAt = .now
            existing.title = title
            existing.channelName = channelName
            existing.thumbnailURL = thumbnailURL
            existing.lastPosition = position
            existing.duration = duration
        } else {
            modelContext.insert(WatchHistoryEntry(
                videoID: videoID,
                title: title,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                lastPosition: position,
                duration: duration
            ))
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
    }

    /// Stores lightweight playback progress without bumping `watchedAt`; opening a video controls
    /// history ordering, while periodic transport ticks should not continuously reorder the list.
    func updateWatchProgress(
        videoID: String,
        position: TimeInterval,
        duration: TimeInterval,
        notifyObservers: Bool = false
    ) {
        let target = videoID
        let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        existing.lastPosition = position
        existing.duration = duration
        try? modelContext.save()
        if notifyObservers {
            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        }
    }

    func updateWatchHistoryMetadata(
        videoID: String,
        title: String,
        channelName: String,
        thumbnailURL: URL?
    ) {
        let target = videoID
        let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        existing.title = title
        existing.channelName = channelName
        existing.thumbnailURL = thumbnailURL
        try? modelContext.save()
    }

    /// Returns the locally stored resume point. Reads share this model actor so they never race a
    /// periodic progress write or touch a `ModelContext` from the main actor.
    func watchProgress(videoID: String) -> (position: TimeInterval, duration: TimeInterval)? {
        let target = videoID
        let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
        guard let existing = try? modelContext.fetch(descriptor).first else { return nil }
        return (existing.lastPosition, existing.duration)
    }

    func watchProgress(videoIDs: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for videoID in Set(videoIDs) {
            let target = videoID
            let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
            guard let entry = try? modelContext.fetch(descriptor).first,
                  let progress = entry.resumableProgress else { continue }
            result[videoID] = progress
        }
        return result
    }

    func fetchWatchHistory(offset: Int, limit: Int) -> [WatchHistorySnapshot] {
        var descriptor = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\WatchHistoryEntry.watchedAt, order: .reverse)]
        )
        descriptor.fetchOffset = max(0, offset)
        descriptor.fetchLimit = max(1, limit)
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.map {
            WatchHistorySnapshot(
                videoID: $0.videoID,
                title: $0.title,
                channelName: $0.channelName,
                thumbnailURL: $0.thumbnailURL,
                watchedAt: $0.watchedAt,
                lastPosition: $0.lastPosition,
                duration: $0.duration
            )
        }
    }

    func watchHistoryCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<WatchHistoryEntry>())) ?? 0
    }

    func deleteWatchHistory(videoID: String) {
        let target = videoID
        let descriptor = FetchDescriptor<WatchHistoryEntry>(predicate: #Predicate { $0.videoID == target })
        if let entry = try? modelContext.fetch(descriptor).first {
            modelContext.delete(entry)
            try? modelContext.save()
            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        }
    }

    func clearWatchHistory() {
        let descriptor = FetchDescriptor<WatchHistoryEntry>()
        guard let entries = try? modelContext.fetch(descriptor) else { return }
        for entry in entries { modelContext.delete(entry) }
        try? modelContext.save()
        NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
    }

}
