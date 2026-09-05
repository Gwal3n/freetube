import Foundation
import SwiftData

extension Notification.Name {
    static let localPlaylistsDidChange = Notification.Name("com.leshko.freetube.localPlaylistsDidChange")
}

@available(iOS 17.0, *)
@ModelActor
actor LocalPlaylistWriter {
    static let shared = LocalPlaylistWriter(modelContainer: PersistenceController.sharedContainer)

    func playlists() -> [LocalPlaylistSnapshot] {
        let records = ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>(
            sortBy: [SortDescriptor(\LocalPlaylistRecord.updatedAt, order: .reverse)]
        ))) ?? [])
        return records.map { record in
            let itemCount = videoCount(playlistID: record.playlistID)
            return LocalPlaylistSnapshot(
                id: record.playlistID,
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videoCount: itemCount,
                thumbnailURL: firstVideoRecord(playlistID: record.playlistID)?.thumbnailURL,
                updatedAt: record.updatedAt,
                metadataHydrationTotal: record.metadataHydrationTotal,
                metadataHydrationProcessed: record.metadataHydrationProcessed,
                metadataHydrationFailures: record.metadataHydrationFailures
            )
        }
    }

    func details(playlistID: String) -> LocalPlaylistDetails? {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return nil }
        let items = videoRecords(playlistID: playlistID)
        return LocalPlaylistDetails(
            playlist: LocalPlaylistSnapshot(
                id: record.playlistID,
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videoCount: items.count,
                thumbnailURL: items.first?.thumbnailURL,
                updatedAt: record.updatedAt,
                metadataHydrationTotal: record.metadataHydrationTotal,
                metadataHydrationProcessed: record.metadataHydrationProcessed,
                metadataHydrationFailures: record.metadataHydrationFailures
            ),
            videos: items.map(Self.video(from:))
        )
    }

    @discardableResult
    func create(title: String, descriptionText: String? = nil, sourcePlaylistID: String? = nil) -> String {
        if let sourcePlaylistID, let existing = record(sourcePlaylistID: sourcePlaylistID) {
            existing.title = title
            existing.descriptionText = descriptionText
            existing.updatedAt = .now
            try? modelContext.save()
            notify()
            return existing.playlistID
        }
        let record = LocalPlaylistRecord(
            title: title,
            descriptionText: descriptionText,
            sourcePlaylistID: sourcePlaylistID
        )
        modelContext.insert(record)
        try? modelContext.save()
        notify()
        return record.playlistID
    }

    func add(video: Video, to playlistID: String) {
        let membership = "\(playlistID):\(video.id)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(predicate: #Predicate { $0.membershipID == membership })
        guard (try? modelContext.fetch(descriptor).first) == nil else { return }
        modelContext.insert(LocalPlaylistVideoRecord(
            playlistID: playlistID,
            video: video,
            position: videoRecords(playlistID: playlistID).count
        ))
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    func contains(videoID: String, playlistID: String) -> Bool {
        let membership = "\(playlistID):\(videoID)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(predicate: #Predicate { $0.membershipID == membership })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    func isInPersonalPlaylist(videoID: String) -> Bool {
        let records = playlists().filter { !$0.isSavedFromYouTube }
        return records.contains { contains(videoID: videoID, playlistID: $0.id) }
    }

    func remove(videoID: String, from playlistID: String) {
        let membership = "\(playlistID):\(videoID)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(predicate: #Predicate { $0.membershipID == membership })
        if let item = try? modelContext.fetch(descriptor).first {
            adjustHydrationForDeletion(item, playlistID: playlistID)
            modelContext.delete(item)
        }
        normalizePositions(playlistID)
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    func remove(videoIDs: Set<String>, from playlistID: String) {
        guard !videoIDs.isEmpty else { return }
        for item in videoRecords(playlistID: playlistID) where videoIDs.contains(item.videoID) {
            adjustHydrationForDeletion(item, playlistID: playlistID)
            modelContext.delete(item)
        }
        normalizePositions(playlistID)
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    func delete(playlistID: String) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        if let record = try? modelContext.fetch(descriptor).first { modelContext.delete(record) }
        for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        try? modelContext.save()
        notify()
    }

    func updatePlaylist(playlistID: String, title: String, descriptionText: String?) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.title = title
        record.descriptionText = descriptionText
        record.updatedAt = .now
        try? modelContext.save()
        notify()
    }

    func isRemotePlaylistSaved(_ sourcePlaylistID: String) -> Bool {
        record(sourcePlaylistID: sourcePlaylistID) != nil
    }

    func deleteRemotePlaylist(_ sourcePlaylistID: String) {
        guard let playlistID = record(sourcePlaylistID: sourcePlaylistID)?.playlistID else { return }
        delete(playlistID: playlistID)
    }

    func replace(
        title: String,
        descriptionText: String? = nil,
        sourcePlaylistID: String?,
        videos: [Video],
        requiresMetadataHydration: Bool = false
    ) -> String {
        let playlistID = create(
            title: title,
            descriptionText: descriptionText,
            sourcePlaylistID: sourcePlaylistID
        )
        for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        for (index, video) in videos.enumerated() {
            modelContext.insert(LocalPlaylistVideoRecord(
                playlistID: playlistID,
                video: video,
                position: index,
                metadataState: requiresMetadataHydration ? 1 : 0
            ))
        }
        setHydrationProgress(
            playlistID: playlistID,
            total: requiresMetadataHydration ? videos.count : 0,
            processed: 0,
            failures: 0
        )
        touch(playlistID)
        try? modelContext.save()
        notify()
        return playlistID
    }

    func moveVideos(playlistID: String, from source: IndexSet, to destination: Int) {
        var items = videoRecords(playlistID: playlistID)
        let moving = source.compactMap { items.indices.contains($0) ? items[$0] : nil }
        for index in source.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = max(0, min(items.count, destination - removedBeforeDestination))
        items.insert(contentsOf: moving, at: insertionIndex)
        for (index, item) in items.enumerated() { item.position = index }
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    func applyHydrationResult(video: Video?, videoID: String, playlistID: String, notifyProgress: Bool) {
        let membership = "\(playlistID):\(videoID)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.membershipID == membership }
        )
        guard let old = try? modelContext.fetch(descriptor).first else { return }
        if let video {
            old.title = video.title
            old.channelID = video.channelID
            old.channelName = video.channelName
            old.channelThumbnailURL = video.channelThumbnailURL
            // Keep the deterministic thumbnail built from the CSV video ID.
            old.duration = video.duration
            old.viewCount = video.viewCount
            old.publishedAt = video.publishedAt
            old.publishedRelative = video.publishedRelative
            old.descriptionSnippet = video.descriptionSnippet
            old.isLive = video.isLive
            old.isShort = video.isShort
            old.metadataState = 0
        } else {
            old.metadataState = 2
        }
        incrementHydrationProgress(playlistID: playlistID, failed: video == nil)
        try? modelContext.save()
        if notifyProgress { notify() }
    }

    func pendingMetadataVideos(playlistID: String) -> [Video] {
        videoRecords(playlistID: playlistID)
            .filter { $0.metadataState == 1 }
            .map(Self.video(from:))
    }

    func retryFailedMetadata(playlistID: String) {
        let failed = videoRecords(playlistID: playlistID).filter { $0.metadataState == 2 }
        guard !failed.isEmpty else { return }
        for item in failed { item.metadataState = 1 }
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        if let record = try? modelContext.fetch(descriptor).first {
            record.metadataHydrationProcessed = max(0, record.metadataHydrationProcessed - failed.count)
            record.metadataHydrationFailures = 0
        }
        try? modelContext.save()
        notify()
    }

    func prepareLegacyImportedMetadata() {
        var changed = false
        let records = (try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>())) ?? []
        for record in records where record.sourcePlaylistID == nil && record.metadataHydrationTotal == 0 {
            let unresolved = videoRecords(playlistID: record.playlistID).filter {
                $0.title == $0.videoID && $0.channelName.isEmpty
            }
            guard !unresolved.isEmpty else { continue }
            for item in unresolved { item.metadataState = 1 }
            record.metadataHydrationTotal = unresolved.count
            record.metadataHydrationProcessed = 0
            record.metadataHydrationFailures = 0
            changed = true
        }
        guard changed else { return }
        try? modelContext.save()
        notify()
    }

    func notifyMetadataProgress() { notify() }

    private func videoRecords(playlistID: String) -> [LocalPlaylistVideoRecord] {
        let target = playlistID
        return ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.playlistID == target },
            sortBy: [SortDescriptor(\LocalPlaylistVideoRecord.position)]
        ))) ?? [])
    }

    private func videoCount(playlistID: String) -> Int {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.playlistID == target }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func firstVideoRecord(playlistID: String) -> LocalPlaylistVideoRecord? {
        let target = playlistID
        var descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.playlistID == target },
            sortBy: [SortDescriptor(\LocalPlaylistVideoRecord.position)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func record(sourcePlaylistID: String) -> LocalPlaylistRecord? {
        let source = sourcePlaylistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.sourcePlaylistID == source })
        return try? modelContext.fetch(descriptor).first
    }

    private func touch(_ playlistID: String) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        if let record = try? modelContext.fetch(descriptor).first { record.updatedAt = .now }
    }

    private func normalizePositions(_ playlistID: String) {
        for (index, item) in videoRecords(playlistID: playlistID).enumerated() { item.position = index }
    }

    private func setHydrationProgress(playlistID: String, total: Int, processed: Int, failures: Int) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.metadataHydrationTotal = total
        record.metadataHydrationProcessed = processed
        record.metadataHydrationFailures = failures
    }

    private func incrementHydrationProgress(playlistID: String, failed: Bool) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.metadataHydrationProcessed = min(
            record.metadataHydrationTotal,
            record.metadataHydrationProcessed + 1
        )
        if failed { record.metadataHydrationFailures += 1 }
    }

    private func adjustHydrationForDeletion(_ item: LocalPlaylistVideoRecord, playlistID: String) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first,
              record.metadataHydrationTotal > 0 else { return }
        record.metadataHydrationTotal = max(0, record.metadataHydrationTotal - 1)
        if item.metadataState != 1 {
            record.metadataHydrationProcessed = max(0, record.metadataHydrationProcessed - 1)
        }
        if item.metadataState == 2 {
            record.metadataHydrationFailures = max(0, record.metadataHydrationFailures - 1)
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .localPlaylistsDidChange, object: nil)
    }

    private static func video(from item: LocalPlaylistVideoRecord) -> Video {
        Video(
            id: item.videoID, title: item.title, channelID: item.channelID,
            channelName: item.channelName, channelThumbnailURL: item.channelThumbnailURL,
            thumbnailURL: item.thumbnailURL, duration: item.duration, viewCount: item.viewCount,
            publishedAt: item.publishedAt, publishedRelative: item.publishedRelative,
            descriptionSnippet: item.descriptionSnippet,
            isLive: item.isLive, isShort: item.isShort
        )
    }
}
