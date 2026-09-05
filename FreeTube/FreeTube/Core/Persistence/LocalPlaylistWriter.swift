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
            let items = videoRecords(playlistID: record.playlistID)
            return LocalPlaylistSnapshot(
                id: record.playlistID,
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videoCount: items.count,
                thumbnailURL: items.first?.thumbnailURL,
                updatedAt: record.updatedAt
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
                updatedAt: record.updatedAt
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
        if let item = try? modelContext.fetch(descriptor).first { modelContext.delete(item) }
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
        videos: [Video]
    ) -> String {
        let playlistID = create(
            title: title,
            descriptionText: descriptionText,
            sourcePlaylistID: sourcePlaylistID
        )
        for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        for (index, video) in videos.enumerated() {
            modelContext.insert(LocalPlaylistVideoRecord(playlistID: playlistID, video: video, position: index))
        }
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

    func update(video: Video, in playlistID: String) {
        let membership = "\(playlistID):\(video.id)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.membershipID == membership }
        )
        guard let old = try? modelContext.fetch(descriptor).first else { return }
        old.title = video.title
        old.channelID = video.channelID
        old.channelName = video.channelName
        old.channelThumbnailURL = video.channelThumbnailURL
        old.thumbnailURL = video.thumbnailURL
        old.duration = video.duration
        old.viewCount = video.viewCount
        old.publishedAt = video.publishedAt
        old.publishedRelative = video.publishedRelative
        old.descriptionSnippet = video.descriptionSnippet
        old.isLive = video.isLive
        old.isShort = video.isShort
        try? modelContext.save()
    }

    func finishMetadataUpdate(playlistID: String) {
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    private func videoRecords(playlistID: String) -> [LocalPlaylistVideoRecord] {
        let target = playlistID
        return ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.playlistID == target },
            sortBy: [SortDescriptor(\LocalPlaylistVideoRecord.position)]
        ))) ?? [])
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
