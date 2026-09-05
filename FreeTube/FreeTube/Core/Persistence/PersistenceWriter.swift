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
/// **What's serialized here:** WatchHistory, FavoriteVideo, SearchHistory writes. (Downloads
/// moved to file-system + xattr storage in `DownloadsStore` — no SwiftData involved.)
/// Reads (favorite lookup, recent history, etc.) still go through SwiftUI `@Query` or the main
/// context — those are reactive and indexed.
@available(iOS 17.0, *)
@ModelActor
actor PersistenceWriter {
    static let shared = PersistenceWriter(modelContainer: PersistenceController.sharedContainer)

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
