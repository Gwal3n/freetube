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
                videoCount: items.count,
                thumbnailURL: items.first?.thumbnailURL,
                updatedAt: record.updatedAt
            ),
            videos: items.map(Self.video(from:))
        )
    }

    @discardableResult
    func create(title: String, sourcePlaylistID: String? = nil) -> String {
        if let sourcePlaylistID, let existing = record(sourcePlaylistID: sourcePlaylistID) {
            existing.title = title
            existing.updatedAt = .now
            try? modelContext.save()
            notify()
            return existing.playlistID
        }
        let record = LocalPlaylistRecord(title: title, sourcePlaylistID: sourcePlaylistID)
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

    func isRemotePlaylistSaved(_ sourcePlaylistID: String) -> Bool {
        record(sourcePlaylistID: sourcePlaylistID) != nil
    }

    func deleteRemotePlaylist(_ sourcePlaylistID: String) {
        guard let playlistID = record(sourcePlaylistID: sourcePlaylistID)?.playlistID else { return }
        delete(playlistID: playlistID)
    }

    func replace(title: String, sourcePlaylistID: String?, videos: [Video]) -> String {
        let playlistID = create(title: title, sourcePlaylistID: sourcePlaylistID)
        for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        for (index, video) in videos.enumerated() {
            modelContext.insert(LocalPlaylistVideoRecord(playlistID: playlistID, video: video, position: index))
        }
        touch(playlistID)
        try? modelContext.save()
        notify()
        return playlistID
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
