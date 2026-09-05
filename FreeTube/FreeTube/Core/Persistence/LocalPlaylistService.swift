import Foundation

@available(iOS 17.0, *)
final class LocalPlaylistService: Sendable {
    private let writer: LocalPlaylistWriter
    private let remoteService: any PlaylistServicing

    init(writer: LocalPlaylistWriter = .shared, remoteService: any PlaylistServicing = PlaylistService()) {
        self.writer = writer
        self.remoteService = remoteService
    }

    func playlists() async -> [LocalPlaylistSnapshot] { await writer.playlists() }
    func details(id: String) async -> LocalPlaylistDetails? { await writer.details(playlistID: id) }
    func create(title: String) async -> String { await writer.create(title: title) }
    func add(video: Video, to playlistID: String) async { await writer.add(video: video, to: playlistID) }
    func remove(videoID: String, from playlistID: String) async { await writer.remove(videoID: videoID, from: playlistID) }
    func delete(id: String) async { await writer.delete(playlistID: id) }
    func contains(videoID: String, playlistID: String) async -> Bool {
        await writer.contains(videoID: videoID, playlistID: playlistID)
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
        _ = await writer.replace(title: title, sourcePlaylistID: playlist.id, videos: videos)
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
        return await writer.replace(title: title.isEmpty ? "Imported playlist" : title, sourcePlaylistID: nil, videos: videos)
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
