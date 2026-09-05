import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct LocalPlaylistScreen: View {
    private enum EditingMode {
        case playlist
    }

    let playlistID: String
    @State private var details: LocalPlaylistDetails?
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showingEditor = false
    @State private var showingRestoreConfirmation = false
    @State private var editingMode: EditingMode?
    @State private var editMode: EditMode = .inactive
    @State private var selectedVideoIDs = Set<String>()
    @State private var showingVideoDeleteConfirmation = false
    @Environment(PlayerStateManager.self) private var player
    private let service = LocalPlaylistService()

    var body: some View {
        List(selection: $selectedVideoIDs) {
            if let details {
                Section {
                    playlistHeader(details)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(details.videos) { video in
                    VideoRow(
                        video: video,
                        showsMoreMenu: editingMode == nil,
                        offersPlayNext: editingMode == nil,
                        reservesMoreMenuSpace: true
                    ) {
                        if editingMode != nil {
                            if selectedVideoIDs.contains(video.id) {
                                selectedVideoIDs.remove(video.id)
                            } else {
                                selectedVideoIDs.insert(video.id)
                            }
                        } else if editingMode == nil {
                            player.loadPlaylist(playbackDetails(from: details), startAt: video)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task {
                                await service.remove(videoID: video.id, from: playlistID)
                                await reload()
                            }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                    .tag(video.id)
                    .moveDisabled(editingMode == nil)
                }
                .onMove { source, destination in
                    guard editingMode != nil else { return }
                    Task {
                        await service.move(playlistID: playlistID, from: source, to: destination)
                        await reload()
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
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
                if editingMode != nil {
                    Button(role: .destructive) {
                        showingVideoDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedVideoIDs.isEmpty)
                    Button("Done") { finishEditing() }
                }
                if editingMode == nil {
                    Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Details", systemImage: "square.and.pencil")
                    }
                    Button {
                        beginEditing()
                    } label: {
                        Label("Edit Playlist", systemImage: "list.bullet")
                    }
                    if details?.playlist.isSavedFromYouTube == true {
                        Button {
                            showingRestoreConfirmation = true
                        } label: {
                            Label("Restore from YouTube", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRestoring)
                    }
                    if let playlist = details?.playlist, playlist.metadataHydrationFailures > 0 {
                        Button {
                            Task {
                                await service.retryFailedMetadata(id: playlistID)
                                await LocalPlaylistHydrationCoordinator.shared.startIfNeeded()
                            }
                        } label: {
                            Label("Retry Video Information", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    } label: {
                        if isRestoring { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                    }
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
        .confirmationDialog(
            "Remove selected videos?",
            isPresented: $showingVideoDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove \(selectedVideoIDs.count) Videos", role: .destructive) {
                Task { await deleteSelectedVideos() }
            }
            Button("Cancel", role: .cancel) {}
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
                HStack(alignment: .center, spacing: 10) {
                    Text(local.playlist.title)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    glassActionButton(systemImage: "play.fill", label: "Play All") {
                        guard let first = local.videos.first else { return }
                        player.loadPlaylist(playbackDetails(from: local), startAt: first)
                    }
                    glassActionButton(systemImage: "shuffle", label: "Shuffle") {
                        guard let random = local.videos.randomElement() else { return }
                        player.loadPlaylist(playbackDetails(from: local), startAt: random, shuffled: true)
                    }
                }
                .disabled(local.videos.isEmpty)
                Text("\(local.playlist.videoCount) \(local.playlist.videoCount == 1 ? "video" : "videos")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let description = local.playlist.descriptionText, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func glassActionButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
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

    private func beginEditing() {
        withAnimation(.snappy) {
            selectedVideoIDs.removeAll()
            editingMode = .playlist
            editMode = .active
        }
    }

    private func finishEditing() {
        withAnimation(.snappy) {
            editMode = .inactive
            editingMode = nil
            selectedVideoIDs.removeAll()
        }
    }

    private func deleteSelectedVideos() async {
        let ids = selectedVideoIDs
        await service.remove(videoIDs: ids, from: playlistID)
        finishEditing()
        await reload()
    }
}
