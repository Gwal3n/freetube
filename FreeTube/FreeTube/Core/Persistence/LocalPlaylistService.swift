import Foundation

@available(iOS 17.0, *)
final class LocalPlaylistService: Sendable {
    private let writer: LocalPlaylistWriter
    private let remoteService: any PlaylistServicing
    private let videoService: any VideoServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "LocalPlaylists")

    init(
        writer: LocalPlaylistWriter = .shared,
        remoteService: any PlaylistServicing = PlaylistService(),
        videoService: any VideoServicing = VideoService()
    ) {
        self.writer = writer
        self.remoteService = remoteService
        self.videoService = videoService
    }

    func playlists() async -> [LocalPlaylistSnapshot] { await writer.playlists() }
    func details(id: String) async -> LocalPlaylistDetails? { await writer.details(playlistID: id) }
    func create(title: String) async -> String { await writer.create(title: title) }
    func add(video: Video, to playlistID: String) async { await writer.add(video: video, to: playlistID) }
    func remove(videoID: String, from playlistID: String) async { await writer.remove(videoID: videoID, from: playlistID) }
    func remove(videoIDs: Set<String>, from playlistID: String) async {
        await writer.remove(videoIDs: videoIDs, from: playlistID)
    }
    func delete(id: String) async { await writer.delete(playlistID: id) }
    func update(id: String, title: String, descriptionText: String?) async {
        await writer.updatePlaylist(playlistID: id, title: title, descriptionText: descriptionText)
    }
    func contains(videoID: String, playlistID: String) async -> Bool {
        await writer.contains(videoID: videoID, playlistID: playlistID)
    }
    func isInPersonalPlaylist(videoID: String) async -> Bool {
        await writer.isInPersonalPlaylist(videoID: videoID)
    }
    func move(playlistID: String, from source: IndexSet, to destination: Int) async {
        await writer.moveVideos(playlistID: playlistID, from: source, to: destination)
    }
    func isRemoteSaved(id: String) async -> Bool { await writer.isRemotePlaylistSaved(id) }
    func removeRemotePlaylist(id: String) async { await writer.deleteRemotePlaylist(id) }

    /// Saves every available page of a public YouTube playlist as a standalone local snapshot.
    func saveRemotePlaylist(_ playlist: Playlist) async throws {
        let details = try await remoteService.fetchPlaylist(id: playlist.id)
        var videos = details.videos
        var continuation = details.continuationToken
        var fetchedTokens = Set<String>()
        while let token = continuation, fetchedTokens.insert(token).inserted {
            try Task.checkCancellation()
            let page = try await remoteService.fetchMore(continuation: token)
            let known = Set(videos.map(\.id))
            videos.append(contentsOf: page.videos.filter { !known.contains($0.id) })
            continuation = page.continuationToken
        }
        let title = details.playlist.title.isEmpty ? playlist.title : details.playlist.title
        _ = await writer.replace(
            title: title,
            descriptionText: details.playlist.descriptionText,
            sourcePlaylistID: playlist.id,
            videos: videos
        )
    }

    func restoreFromYouTube(sourcePlaylistID: String) async throws {
        let placeholder = Playlist(
            id: sourcePlaylistID, title: "", channelID: nil, channelName: nil,
            thumbnailURL: nil, videoCount: nil, descriptionText: nil, isOwnedByUser: false
        )
        try await saveRemotePlaylist(placeholder)
    }

    @discardableResult
    func importCSV(data: Data, filename: String) async throws -> String {
        guard var text = String(data: data, encoding: .utf8) else { throw LocalPlaylistImportError.invalidCSV }
        if text.first == "\u{feff}" { text.removeFirst() }
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first else { throw LocalPlaylistImportError.invalidCSV }
        let columns = Self.csvFields(header).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let idColumn = columns.firstIndex(of: "video id") else { throw LocalPlaylistImportError.invalidCSV }

        var seen = Set<String>()
        let videoIDs = lines.dropFirst().compactMap { line -> String? in
            let fields = Self.csvFields(line)
            guard fields.indices.contains(idColumn) else { return nil }
            let id = fields[idColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
        guard !videoIDs.isEmpty else { throw LocalPlaylistImportError.noVideos }

        let rawName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let title = rawName.hasSuffix("-videos") ? String(rawName.dropLast(7)) : rawName
        let videos = videoIDs.map { id in
            Video(
                id: id, title: id, channelID: "", channelName: "",
                channelThumbnailURL: nil,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
                duration: nil, viewCount: nil, publishedAt: nil, descriptionSnippet: nil,
                isLive: false, isShort: false
            )
        }
        log.info("CSV staged playlist=\(title, privacy: .public) videos=\(videos.count, privacy: .public)")
        return await writer.replace(
            title: title.isEmpty ? "Imported playlist" : title,
            sourcePlaylistID: nil,
            videos: videos,
            requiresMetadataHydration: true
        )
    }

    func prepareLegacyImports() async { await writer.prepareLegacyImportedMetadata() }

    func playlistsAwaitingMetadata() async -> [LocalPlaylistSnapshot] {
        await writer.playlists().filter(\.isHydratingMetadata)
    }

    func hydratePendingPlaylist(id playlistID: String) async {
        let candidates = await writer.pendingMetadataVideos(playlistID: playlistID)
        log.info("Metadata hydration started playlist=\(playlistID, privacy: .public) remaining=\(candidates.count, privacy: .public)")
        var failures = 0
        for (index, placeholder) in candidates.enumerated() {
            guard !Task.isCancelled else {
                await writer.notifyMetadataProgress()
                return
            }
            let resolved: Video?
            do {
                resolved = try await resolveImportedMetadata(for: placeholder)
            } catch {
                resolved = nil
                failures += 1
                log.error("Metadata hydration failed video=\(placeholder.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            let shouldPublishProgress = (index + 1).isMultiple(of: 5) || index == candidates.count - 1
            await writer.applyHydrationResult(
                video: resolved,
                videoID: placeholder.id,
                playlistID: playlistID,
                notifyProgress: shouldPublishProgress
            )
            try? await Task.sleep(for: .milliseconds(200))
        }
        log.info("Metadata hydration finished playlist=\(playlistID, privacy: .public) processed=\(candidates.count, privacy: .public) failures=\(failures, privacy: .public)")
    }

    /// The player-info endpoint can reject a video even when its watch metadata remains public.
    /// Try it first because it provides richer counts, then independently fall back to the watch
    /// metadata response rather than marking the imported ID unavailable.
    private func resolveImportedMetadata(for placeholder: Video) async throws -> Video {
        do {
            let info = try await videoService.fetchInfo(id: placeholder.id)
            guard !info.video.title.isEmpty else { throw LocalPlaylistImportError.noVideos }
            return importedVideo(from: info, placeholder: placeholder)
        } catch {
            log.notice("Player metadata unavailable for \(placeholder.id, privacy: .public); trying watch metadata")
            let info = try await videoService.fetchMoreInfo(id: placeholder.id)
            guard !info.video.title.isEmpty else { throw LocalPlaylistImportError.noVideos }
            return importedVideo(from: info, placeholder: placeholder)
        }
    }

    private func importedVideo(from info: VideoInfo, placeholder: Video) -> Video {
        let video = info.video
        return Video(
            id: placeholder.id,
            title: video.title.isEmpty ? placeholder.id : video.title,
            channelID: video.channelID,
            channelName: video.channelName,
            channelThumbnailURL: video.channelThumbnailURL,
            thumbnailURL: placeholder.thumbnailURL,
            duration: video.duration ?? placeholder.duration,
            viewCount: video.viewCount ?? placeholder.viewCount,
            publishedAt: video.publishedAt ?? placeholder.publishedAt,
            publishedRelative: info.uploadDateText ?? video.publishedRelative,
            descriptionSnippet: info.descriptionText ?? video.descriptionSnippet,
            isLive: video.isLive,
            isShort: video.isShort
        )
    }

    func retryFailedMetadata(id playlistID: String) async {
        await writer.retryFailedMetadata(playlistID: playlistID)
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields = [String]()
        var field = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else { quoted.toggle() }
            } else if character == ",", !quoted {
                fields.append(field); field = ""
            } else { field.append(character) }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
