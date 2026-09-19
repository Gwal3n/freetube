import Foundation
import OSLog
import YouTubeKit

protocol PlaylistServicing: Sendable {
    func fetchPlaylist(id: String) async throws -> PlaylistDetails
    func fetchMore(continuation: String) async throws -> PlaylistDetails
}

/// Anonymous, read-only wrapper around `PlaylistInfosResponse` and its continuation.
final class PlaylistService: PlaylistServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlaylistService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    /// Loads a playlist's header (title, description, owning channel, total view/video counts)
    /// plus its first page of videos. YouTubeKit expects the playlist ID prefixed with `VL` for
    /// browse requests; we add it here if the caller passed the bare ID we get from search/channel
    /// listings.
    func fetchPlaylist(id: String) async throws -> PlaylistDetails {
        log.info("Fetching playlist \(id, privacy: .public)")
        let browseID = id.hasPrefix("VL") ? id : "VL" + id
        let response: PlaylistInfosResponse
        do {
            response = try await PlaylistInfosResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.browseId: browseID]
            )
        } catch {
            log.error("PlaylistInfosResponse failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.network(error)
        }
        return mapDetails(response: response, fallbackID: id)
    }

    func fetchMore(continuation: String) async throws -> PlaylistDetails {
        let response: PlaylistInfosResponse.Continuation
        do {
            response = try await PlaylistInfosResponse.Continuation.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.continuation: continuation]
            )
        } catch {
            throw YouTubeServiceError.network(error)
        }
        let videos = response.results.map(Mappers.video(from:))
        let placeholder = Playlist(id: "", title: "", channelID: nil, channelName: nil, thumbnailURL: nil, videoCount: nil, descriptionText: nil, isOwnedByUser: false)
        return PlaylistDetails(playlist: placeholder, videos: videos, continuationToken: response.continuationToken)
    }

    private func mapDetails(response: PlaylistInfosResponse, fallbackID: String) -> PlaylistDetails {
        let owner = response.channel.first
        let playlist = Playlist(
            id: response.playlistId ?? fallbackID,
            title: response.title ?? "",
            channelID: owner?.channelId,
            channelName: owner?.name,
            thumbnailURL: Mappers.bestThumbnailURL(response.thumbnails),
            videoCount: parseInteger(response.videoCount),
            viewCount: Mappers.parseAbbreviatedCount(response.viewCount),
            descriptionText: response.playlistDescription,
            // Account-free builds never expose remote ownership or editing, even if an
            // anonymous response happens to contain an interaction renderer.
            isOwnedByUser: false
        )
        // Backfill the owning channel's name onto videos that lack one (lockup-decoded items
        // skip the channel field entirely).
        let ownerName = owner?.name ?? ""
        let ownerID = owner?.channelId ?? ""
        let ownerThumb = Mappers.bestThumbnailURL(owner?.thumbnails ?? [])
        let videos: [Video] = response.results.map { yt in
            let v = Mappers.video(from: yt)
            return Video(
                id: v.id,
                title: v.title,
                channelID: v.channelID.isEmpty ? ownerID : v.channelID,
                channelName: v.channelName.isEmpty ? ownerName : v.channelName,
                channelThumbnailURL: v.channelThumbnailURL ?? ownerThumb,
                thumbnailURL: v.thumbnailURL,
                duration: v.duration,
                viewCount: v.viewCount,
                publishedAt: v.publishedAt,
                publishedRelative: v.publishedRelative,
                descriptionSnippet: v.descriptionSnippet,
                isLive: v.isLive,
                isShort: v.isShort
            )
        }
        return PlaylistDetails(playlist: playlist, videos: videos, continuationToken: response.continuationToken)
    }

    private func parseInteger(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        return Int(raw.filter(\.isNumber))
    }

}
