import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct LocalPlaylistScreen: View {
    let playlistID: String
    @State private var details: LocalPlaylistDetails?
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showingEditor = false
    @State private var showingRestoreConfirmation = false
    @Environment(PlayerStateManager.self) private var player
    private let service = LocalPlaylistService()

    var body: some View {
        List {
            if let details {
                Section {
                    playlistHeader(details)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
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
                .onMove { source, destination in
                    Task {
                        await service.move(playlistID: playlistID, from: source, to: destination)
                        await reload()
                    }
                }
            }
        }
        .navigationTitle(details?.playlist.title ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let details, details.videos.isEmpty {
                ContentUnavailableView("Empty Playlist", systemImage: "music.note.list")
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await reload() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    if details?.playlist.isSavedFromYouTube == true {
                        Button {
                            showingRestoreConfirmation = true
                        } label: {
                            Label("Restore from YouTube", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRestoring)
                    }
                } label: {
                    if isRestoring { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .alert("Couldn’t Restore Playlist", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
        .sheet(isPresented: $showingEditor) {
            if let playlist = details?.playlist {
                EditLocalPlaylistSheet(playlist: playlist) { title, description in
                    await service.update(id: playlistID, title: title, descriptionText: description)
                    await reload()
                }
            }
        }
        .confirmationDialog(
            "Restore the original playlist?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore from YouTube", role: .destructive) {
                Task { await restore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local ordering, removals, and description edits will be replaced with the current public playlist.")
        }
    }

    private func reload() async { details = await service.details(id: playlistID) }

    private func playbackDetails(from local: LocalPlaylistDetails) -> PlaylistDetails {
        PlaylistDetails(
            playlist: Playlist(
                id: "local:\(local.playlist.id)", title: local.playlist.title,
                channelID: nil, channelName: nil, thumbnailURL: local.playlist.thumbnailURL,
                videoCount: local.playlist.videoCount,
                descriptionText: local.playlist.descriptionText,
                isOwnedByUser: true
            ),
            videos: local.videos,
            continuationToken: nil
        )
    }

    private func playlistHeader(_ local: LocalPlaylistDetails) -> some View {
        VStack(spacing: 14) {
            KFImage(local.playlist.thumbnailURL)
                .placeholder { Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary) }
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(local.playlist.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(local.playlist.videoCount) \(local.playlist.videoCount == 1 ? "video" : "videos")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let description = local.playlist.descriptionText, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                HStack(spacing: 12) {
                    Button {
                        guard let first = local.videos.first else { return }
                        player.loadPlaylist(playbackDetails(from: local), startAt: first)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        guard let random = local.videos.randomElement() else { return }
                        player.loadPlaylist(playbackDetails(from: local), startAt: random, shuffled: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(local.videos.isEmpty)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func restore() async {
        guard let sourceID = details?.playlist.sourcePlaylistID, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await service.restoreFromYouTube(sourcePlaylistID: sourceID)
            await reload()
        } catch {
            restoreError = error.localizedDescription
        }
    }
}
