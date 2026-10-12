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
        let records = ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>())) ?? [])
            .sorted {
                if $0.sortPosition != $1.sortPosition { return $0.sortPosition < $1.sortPosition }
                return $0.createdAt < $1.createdAt
            }
        let refreshJobs = (try? modelContext.fetch(FetchDescriptor<LocalPlaylistRefreshJob>())) ?? []
        let refreshByPlaylist = refreshJobs.reduce(into: [String: LocalPlaylistRefreshJob]()) {
            $0[$1.playlistID] = $1
        }
        return records.map { record in
            let itemCount = videoCount(playlistID: record.playlistID)
            let refresh = refreshByPlaylist[record.playlistID]
            return LocalPlaylistSnapshot(
                id: record.playlistID,
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videoCount: itemCount,
                thumbnailURL: firstVideoRecord(playlistID: record.playlistID)?.thumbnailURL,
                customArtworkData: record.customArtworkData,
                updatedAt: record.updatedAt,
                metadataHydrationTotal: record.metadataHydrationTotal,
                metadataHydrationProcessed: record.metadataHydrationProcessed,
                metadataHydrationFailures: record.metadataHydrationFailures,
                metadataRefreshTotal: refresh?.total ?? 0,
                metadataRefreshProcessed: refresh?.nextIndex ?? 0,
                metadataRefreshFailures: refresh?.failures ?? 0
            )
        }
    }

    /// Searches saved video metadata across local playlists. Return one matching title per
    /// playlist so the Library can explain why a playlist with a different name appears.
    /// Fetch in bounded pages rather than materializing every imported video at once.
    func playlistsMatchingVideo(query: String) -> [String: String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return [:] }

        var matches: [String: String] = [:]
        var offset = 0
        let pageSize = 400
        while !Task.isCancelled {
            var descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
                sortBy: [SortDescriptor(\LocalPlaylistVideoRecord.membershipID)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            guard let page = try? modelContext.fetch(descriptor) else { break }
            for item in page where matches[item.playlistID] == nil {
                if item.title.localizedStandardContains(search)
                    || item.channelName.localizedStandardContains(search)
                    || item.videoID.localizedStandardContains(search) {
                    matches[item.playlistID] = item.title
                }
            }
            guard page.count == pageSize else { break }
            offset += page.count
        }
        return matches
    }

    func details(playlistID: String) -> LocalPlaylistDetails? {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return nil }
        let items = videoRecords(playlistID: playlistID)
        let refresh = refreshJob(playlistID: playlistID)
        return LocalPlaylistDetails(
            playlist: LocalPlaylistSnapshot(
                id: record.playlistID,
                title: record.title,
                descriptionText: record.descriptionText,
                sourcePlaylistID: record.sourcePlaylistID,
                videoCount: items.count,
                thumbnailURL: items.first?.thumbnailURL,
                customArtworkData: record.customArtworkData,
                updatedAt: record.updatedAt,
                metadataHydrationTotal: record.metadataHydrationTotal,
                metadataHydrationProcessed: record.metadataHydrationProcessed,
                metadataHydrationFailures: record.metadataHydrationFailures,
                metadataRefreshTotal: refresh?.total ?? 0,
                metadataRefreshProcessed: refresh?.nextIndex ?? 0,
                metadataRefreshFailures: refresh?.failures ?? 0
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
        record.sortPosition = nextPlaylistPosition()
        modelContext.insert(record)
        try? modelContext.save()
        notify()
        return record.playlistID
    }

    func add(video: Video, to playlistID: String) {
        let membership = "\(playlistID):\(video.id)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(predicate: #Predicate { $0.membershipID == membership })
        guard (try? modelContext.fetch(descriptor).first) == nil else { return }
        let existing = videoRecords(playlistID: playlistID)
        let firstPosition = existing.first?.position ?? 1
        let newPosition: Int
        if firstPosition == Int.min {
            // An extremely old playlist can exhaust descending positions; compact only then.
            for (index, item) in existing.enumerated() { item.position = index + 1 }
            newPosition = 0
        } else {
            newPosition = firstPosition - 1
        }
        modelContext.insert(LocalPlaylistVideoRecord(
            playlistID: playlistID,
            video: video,
            position: newPosition
        ))
        touch(playlistID)
        try? modelContext.save()
        notify()
    }

    /// Append a queue snapshot in playback order, keeping existing entries in place.
    /// A single save/notification avoids reloading the playlist for every queued video.
    func append(videos: [Video], to playlistID: String) {
        guard !videos.isEmpty else { return }
        let target = playlistID
        let playlistDescriptor = FetchDescriptor<LocalPlaylistRecord>(
            predicate: #Predicate { $0.playlistID == target }
        )
        guard (try? modelContext.fetch(playlistDescriptor).first) != nil else { return }

        let existing = videoRecords(playlistID: playlistID)
        var knownIDs = Set(existing.map(\.videoID))
        let additions = videos.filter { knownIDs.insert($0.id).inserted }
        guard !additions.isEmpty else { return }

        // Normalize first so old playlists with negative prepend positions can append safely.
        for (index, item) in existing.enumerated() { item.position = index }
        for (index, video) in additions.enumerated() {
            modelContext.insert(LocalPlaylistVideoRecord(
                playlistID: playlistID,
                video: video,
                position: existing.count + index
            ))
        }
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
        if let job = refreshJob(playlistID: playlistID) { modelContext.delete(job) }
        for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        try? modelContext.save()
        normalizePlaylistPositions()
        notify()
    }

    func reorderPlaylists(_ orderedIDs: [String]) {
        let records = (try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>())) ?? []
        let positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        for record in records {
            if let position = positions[record.playlistID] { record.sortPosition = position }
        }
        try? modelContext.save()
        notify()
    }

    func deletePlaylists(_ playlistIDs: Set<String>) {
        guard !playlistIDs.isEmpty else { return }
        for playlistID in playlistIDs {
            let target = playlistID
            let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
            if let record = try? modelContext.fetch(descriptor).first { modelContext.delete(record) }
            if let job = refreshJob(playlistID: playlistID) { modelContext.delete(job) }
            for item in videoRecords(playlistID: playlistID) { modelContext.delete(item) }
        }
        try? modelContext.save()
        normalizePlaylistPositions()
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

    func setArtwork(playlistID: String, data: Data?) {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRecord>(predicate: #Predicate { $0.playlistID == target })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.customArtworkData = data
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
        if let job = refreshJob(playlistID: playlistID) { modelContext.delete(job) }
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
            old.publishedAt = video.estimatedPublishedAt(relativeTo: .now)
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

    /// Queue one explicit refresh over the current membership. A running job is never reset by
    /// reopening the screen or tapping the action twice; its checkpoint remains authoritative.
    func scheduleMetadataRefresh(playlistID: String) -> Bool {
        let target = playlistID
        let playlistDescriptor = FetchDescriptor<LocalPlaylistRecord>(
            predicate: #Predicate { $0.playlistID == target }
        )
        guard let playlist = try? modelContext.fetch(playlistDescriptor).first,
              playlist.metadataHydrationProcessed >= playlist.metadataHydrationTotal else { return false }
        if let active = refreshJob(playlistID: playlistID), active.nextIndex < active.total {
            return true
        }
        let videoIDs = videoRecords(playlistID: playlistID).map(\.videoID)
        guard !videoIDs.isEmpty,
              let data = try? JSONEncoder().encode(videoIDs),
              let encoded = String(data: data, encoding: .utf8) else { return false }
        if let existing = refreshJob(playlistID: playlistID) {
            existing.videoIDsJSON = encoded
            existing.nextIndex = 0
            existing.total = videoIDs.count
            existing.failures = 0
            existing.startedAt = .now
        } else {
            modelContext.insert(LocalPlaylistRefreshJob(
                playlistID: playlistID, videoIDsJSON: encoded, total: videoIDs.count
            ))
        }
        try? modelContext.save()
        notify()
        return true
    }

    func playlistsAwaitingMetadataRefresh() -> [String] {
        ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistRefreshJob>())) ?? [])
            .filter { $0.nextIndex < $0.total }
            .sorted { $0.startedAt < $1.startedAt }
            .map(\.playlistID)
    }

    /// Missing/deleted memberships advance without a request. The next index is saved with
    /// each successful result, so an interrupted lookup is the only item retried on relaunch.
    func nextMetadataRefreshVideo(playlistID: String) -> Video? {
        guard let job = refreshJob(playlistID: playlistID), job.nextIndex < job.total else { return nil }
        let target = playlistID
        let playlistDescriptor = FetchDescriptor<LocalPlaylistRecord>(
            predicate: #Predicate { $0.playlistID == target }
        )
        guard (try? modelContext.fetch(playlistDescriptor).first) != nil else {
            modelContext.delete(job)
            try? modelContext.save()
            notify()
            return nil
        }
        guard let data = job.videoIDsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              ids.count == job.total else {
            job.failures += max(0, job.total - job.nextIndex)
            job.nextIndex = job.total
            job.videoIDsJSON = ""
            try? modelContext.save()
            notify()
            return nil
        }
        var skipped = false
        while job.nextIndex < ids.count {
            let membership = "\(playlistID):\(ids[job.nextIndex])"
            let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
                predicate: #Predicate { $0.membershipID == membership }
            )
            if let item = try? modelContext.fetch(descriptor).first {
                if skipped {
                    try? modelContext.save()
                    notify()
                }
                return Self.video(from: item)
            }
            job.nextIndex += 1
            skipped = true
        }
        job.videoIDsJSON = ""
        try? modelContext.save()
        notify()
        return nil
    }

    /// Merge only data that the anonymous response actually supplied. One SwiftData save commits
    /// the new metadata and the checkpoint, preserving edits/order and old data on a failed lookup.
    func completeMetadataRefresh(videoID: String, playlistID: String, refreshed: Video?) {
        guard let job = refreshJob(playlistID: playlistID), job.nextIndex < job.total,
              let data = job.videoIDsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              ids.indices.contains(job.nextIndex), ids[job.nextIndex] == videoID else { return }
        let membership = "\(playlistID):\(videoID)"
        let descriptor = FetchDescriptor<LocalPlaylistVideoRecord>(
            predicate: #Predicate { $0.membershipID == membership }
        )
        if let item = try? modelContext.fetch(descriptor).first, let refreshed {
            if !refreshed.title.isEmpty { item.title = refreshed.title }
            if !refreshed.channelID.isEmpty { item.channelID = refreshed.channelID }
            if !refreshed.channelName.isEmpty { item.channelName = refreshed.channelName }
            if let image = refreshed.channelThumbnailURL { item.channelThumbnailURL = image }
            if let image = refreshed.thumbnailURL { item.thumbnailURL = image }
            if let duration = refreshed.duration, duration.isFinite, duration > 0 { item.duration = duration }
            if let views = refreshed.viewCount { item.viewCount = views }
            if let date = refreshed.estimatedPublishedAt(relativeTo: .now) { item.publishedAt = date }
            if let relative = refreshed.publishedRelative, !relative.isEmpty {
                item.publishedRelative = relative
            }
            if let description = refreshed.descriptionSnippet, !description.isEmpty {
                item.descriptionSnippet = description
            }
            item.isLive = refreshed.isLive
            item.isShort = refreshed.isShort
        } else if refreshed == nil {
            job.failures += 1
        }
        job.nextIndex += 1
        if job.nextIndex == job.total { job.videoIDsJSON = "" }
        try? modelContext.save()
        notify()
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

    private func refreshJob(playlistID: String) -> LocalPlaylistRefreshJob? {
        let target = playlistID
        let descriptor = FetchDescriptor<LocalPlaylistRefreshJob>(
            predicate: #Predicate { $0.playlistID == target }
        )
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

    private func nextPlaylistPosition() -> Int {
        let records = (try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>())) ?? []
        return (records.map(\.sortPosition).max() ?? -1) + 1
    }

    private func normalizePlaylistPositions() {
        let records = ((try? modelContext.fetch(FetchDescriptor<LocalPlaylistRecord>())) ?? [])
            .sorted {
                if $0.sortPosition != $1.sortPosition { return $0.sortPosition < $1.sortPosition }
                return $0.createdAt < $1.createdAt
            }
        for (index, record) in records.enumerated() { record.sortPosition = index }
        try? modelContext.save()
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
            publishedAt: item.publishedAt ?? Video.estimatedPublishedAt(
                from: item.publishedRelative, relativeTo: item.addedAt
            ), publishedRelative: item.publishedRelative,
            descriptionSnippet: item.descriptionSnippet,
            isLive: item.isLive, isShort: item.isShort
        )
    }
}
