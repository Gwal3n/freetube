import SwiftUI

/// Offline-first view of a playlist's ordered members. The playlist record groups existing
/// files; opening an unavailable row never silently streams it over the network.
@available(iOS 17.0, *)
struct DownloadedPlaylistScreen: View {
    @Environment(PlayerStateManager.self) private var player
    @State private var coordinator = PlaylistDownloadCoordinator.shared
    @State private var downloads = DownloadsStore.shared
    @State private var blocklist = VideoBlocklist.shared

    let playlistID: String

    private var manifest: PlaylistDownloadManifest? { coordinator.manifest(for: playlistID) }

    private var availableIDs: Set<String> {
        Set(downloads.entries.map(\.videoID))
    }

    var body: some View {
        List {
            if let manifest {
                Section {
                    ForEach(manifest.videos.indices.filter { !blocklist.blocks(manifest.videos[$0]) }, id: \.self) { index in
                        let video = manifest.videos[index]
                        let available = availableIDs.contains(video.id)
                        Button {
                            guard available else { return }
                            let offlineVideos = manifest.videos.filter {
                                availableIDs.contains($0.id) && !blocklist.blocks($0)
                            }
                            let details = PlaylistDetails(
                                playlist: Playlist(
                                    id: manifest.id,
                                    title: manifest.title,
                                    channelID: nil,
                                    channelName: nil,
                                    thumbnailURL: manifest.thumbnailURL,
                                    videoCount: offlineVideos.count,
                                    descriptionText: nil,
                                    isOwnedByUser: false
                                ),
                                videos: offlineVideos,
                                continuationToken: nil
                            )
                            player.loadPlaylist(details, startAt: video, origin: .downloaded)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 25, alignment: .trailing)
                                VideoThumbnail(video: video, size: CGSize(width: 96, height: 54))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(video.title).font(.subheadline).lineLimit(2)
                                    Text(available ? video.channelName : "Not downloaded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if available {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                } header: {
                    let visibleVideos = manifest.videos.filter { !blocklist.blocks($0) }
                    Text("\(visibleVideos.filter { availableIDs.contains($0.id) }.count) of \(visibleVideos.count) downloaded")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(manifest?.title ?? "Playlist")
        .toolbar {
            if let manifest,
               !coordinator.removingPlaylistIDs.contains(manifest.id),
               manifest.status == .paused || (manifest.status == .finished && availableIDs.intersection(Set(manifest.videos.map(\.id))).count < manifest.videos.count) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Resume") { coordinator.resume(manifest.id) }
                }
            }
        }
    }
}
