import Foundation

/// Resolves an optional saved playlist without delaying the History video's own stream request.
/// Removed playlists and videos that moved out of a playlist simply return nil.
@available(iOS 17.0, *)
@MainActor
final class HistoryPlaylistRestorationService {
    private let localPlaylists: LocalPlaylistService
    private let remotePlaylists: any PlaylistServicing

    init(
        localPlaylists: LocalPlaylistService = LocalPlaylistService(),
        remotePlaylists: any PlaylistServicing = PlaylistService()
    ) {
        self.localPlaylists = localPlaylists
        self.remotePlaylists = remotePlaylists
    }

    func restore(for entry: WatchHistorySnapshot) async throws -> PlaylistDetails? {
        guard let playlistID = entry.playlistID,
              let origin = entry.playlistOrigin else { return nil }
        switch origin {
        case .local:
            let localID = playlistID.hasPrefix("local:")
                ? String(playlistID.dropFirst(6)) : playlistID
            guard let local = await localPlaylists.details(id: localID),
                  local.videos.contains(where: { $0.id == entry.videoID }) else { return nil }
            return local.playbackDetails

        case .downloaded:
            guard let manifest = PlaylistDownloadCoordinator.shared.manifest(for: playlistID) else { return nil }
            let downloads = DownloadsStore.shared
            var scanWaits = 0
            while downloads.isScanning && scanWaits < 50 {
                try await Task.sleep(for: .milliseconds(100))
                scanWaits += 1
            }
            try Task.checkCancellation()
            let availableIDs = Set(downloads.entries.map(\.videoID))
            let videos = manifest.videos.filter { availableIDs.contains($0.id) }
            guard videos.contains(where: { $0.id == entry.videoID }) else { return nil }
            return PlaylistDetails(
                playlist: Playlist(
                    id: manifest.id,
                    title: manifest.title,
                    channelID: nil,
                    channelName: nil,
                    thumbnailURL: manifest.thumbnailURL,
                    videoCount: videos.count,
                    descriptionText: nil,
                    isOwnedByUser: false
                ),
                videos: videos,
                continuationToken: nil
            )

        case .youtube:
            let first = try await remotePlaylists.fetchPlaylist(id: playlistID)
            try Task.checkCancellation()
            var videos = first.videos
            var continuation = first.continuationToken
            var seenTokens = Set<String>()
            // A saved video can be beyond the initial public-playlist page. Keep this bounded;
            // playback has already begun, and a very deep/missing item can safely stay standalone.
            for _ in 0..<20 {
                if videos.contains(where: { $0.id == entry.videoID }) { break }
                guard let token = continuation, seenTokens.insert(token).inserted else { break }
                let page = try await remotePlaylists.fetchMore(continuation: token)
                try Task.checkCancellation()
                let knownIDs = Set(videos.map(\.id))
                videos.append(contentsOf: page.videos.filter { !knownIDs.contains($0.id) })
                continuation = page.continuationToken
            }
            guard videos.contains(where: { $0.id == entry.videoID }) else { return nil }
            return PlaylistDetails(
                playlist: first.playlist,
                videos: videos,
                continuationToken: continuation
            )
        }
    }
}
