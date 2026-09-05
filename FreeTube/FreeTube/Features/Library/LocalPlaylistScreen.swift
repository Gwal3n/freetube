import SwiftUI

@available(iOS 17.0, *)
struct LocalPlaylistScreen: View {
    let playlistID: String
    @State private var details: LocalPlaylistDetails?
    @Environment(PlayerStateManager.self) private var player
    private let service = LocalPlaylistService()

    var body: some View {
        List {
            if let details {
                ForEach(details.videos) { video in
                    VideoRow(video: video, showsMoreMenu: true, offersPlayNext: true) {
                        player.loadPlaylist(playbackDetails(from: details), startAt: video)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task {
                                await service.remove(videoID: video.id, from: playlistID)
                                await reload()
                            }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle(details?.playlist.title ?? "Playlist")
        .overlay {
            if let details, details.videos.isEmpty {
                ContentUnavailableView("Empty Playlist", systemImage: "music.note.list")
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await reload() }
        }
    }

    private func reload() async { details = await service.details(id: playlistID) }

    private func playbackDetails(from local: LocalPlaylistDetails) -> PlaylistDetails {
        PlaylistDetails(
            playlist: Playlist(
                id: "local:\(local.playlist.id)", title: local.playlist.title,
                channelID: nil, channelName: nil, thumbnailURL: local.playlist.thumbnailURL,
                videoCount: local.playlist.videoCount, descriptionText: nil, isOwnedByUser: true
            ),
            videos: local.videos,
            continuationToken: nil
        )
    }
}
