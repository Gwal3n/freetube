import SwiftUI
import Kingfisher
import UIKit

@available(iOS 17.0, *)
struct LocalPlaylistsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var hasLoaded = false
    @State private var showingCreate = false
    @State private var newTitle = ""
    @State private var editMode: EditMode = .inactive
    @State private var selectedPlaylistIDs = Set<String>()
    @State private var showingDeleteConfirmation = false
    @State private var editingPlaylist: LocalPlaylistSnapshot?
    @State private var pendingContextDeletion: LocalPlaylistSnapshot?
    @State private var playlistDownloads = PlaylistDownloadCoordinator.shared
    @State private var downloads = DownloadsStore.shared
    private let service = LocalPlaylistService()

    var body: some View {
        List(selection: $selectedPlaylistIDs) {
            playlistSection("Personal", items: personalPlaylists, savedFromYouTube: false)
            playlistSection("Saved from YouTube", items: savedPlaylists, savedFromYouTube: true)
        }
        .environment(\.editMode, $editMode)
        .initialContentLoading(hasLoaded: hasLoaded)
        .navigationTitle("Local Playlists")
        .overlay {
            if hasLoaded && playlists.isEmpty {
                ContentUnavailableView(
                    "No local playlists",
                    systemImage: "music.note.list",
                    description: Text("Create a playlist here or import playlists from Settings.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !editMode.isEditing {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    Button("Edit") { beginEditing() }
                } else {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedPlaylistIDs.isEmpty)
                    Button("Done") { finishEditing() }
                }
            }
        }
        .alert("New Playlist", isPresented: $showingCreate) {
            TextField("Playlist name", text: $newTitle)
            Button("Create") { Task { await create() } }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .task {
            await reload()
            await LocalPlaylistHydrationCoordinator.shared.startIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await reload() }
        }
        .confirmationDialog(
            "Delete selected playlists?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedPlaylistIDs.count) Playlists", role: .destructive) {
                Task { await deleteSelectedPlaylists() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected playlists and their locally saved entries.")
        }
        .confirmationDialog(
            "Delete playlist?",
            isPresented: Binding(
                get: { pendingContextDeletion != nil },
                set: { if !$0 { pendingContextDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                guard let id = pendingContextDeletion?.id else { return }
                pendingContextDeletion = nil
                Task {
                    await service.delete(id: id)
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) { pendingContextDeletion = nil }
        } message: {
            Text("This removes the local playlist and its saved entries.")
        }
        .sheet(item: $editingPlaylist) { playlist in
            EditLocalPlaylistSheet(playlist: playlist) { title, description in
                await service.update(id: playlist.id, title: title, descriptionText: description)
                await reload()
            }
        }
    }

    private func reload() async {
        let loaded = await service.playlists()
        guard !Task.isCancelled else { return }
        playlists = loaded
        hasLoaded = true
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = await service.create(title: title)
        newTitle = ""
        await reload()
    }

    @ViewBuilder
    private func playlistSection(
        _ title: String,
        items: [LocalPlaylistSnapshot],
        savedFromYouTube: Bool
    ) -> some View {
        if !items.isEmpty {
            Section(title) {
                let availableIDs = Set(downloads.entries.map(\.videoID))
                ForEach(items) { playlist in
                    playlistLink(playlist, availableIDs: availableIDs)
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil }
                    Task {
                        for id in ids { await service.delete(id: id) }
                        await reload()
                    }
                }
                .onMove { source, destination in
                    movePlaylists(
                        in: items,
                        from: source,
                        to: destination,
                        savedFromYouTube: savedFromYouTube
                    )
                }
            }
        }
    }

    private func playlistLink(_ playlist: LocalPlaylistSnapshot, availableIDs: Set<String>) -> some View {
        NavigationLink {
            LocalPlaylistScreen(playlistID: playlist.id)
        } label: {
            playlistLabel(playlist, availableIDs: availableIDs)
        }
    }

    @ViewBuilder
    private func playlistLabel(_ playlist: LocalPlaylistSnapshot, availableIDs: Set<String>) -> some View {
        if editMode.isEditing {
            playlistRow(playlist, availableIDs: availableIDs)
        } else {
            playlistRow(playlist, availableIDs: availableIDs)
                .contextMenu {
                    Button { editingPlaylist = playlist } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    if let url = remoteURL(for: playlist) {
                        ShareLink(item: url) {
                            Label("Share playlist", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.url = url
                        } label: {
                            Label("Copy link", systemImage: "link")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { pendingContextDeletion = playlist } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                } preview: {
                    PlaylistContextPreview(playlist: Playlist(
                        id: playlist.sourcePlaylistID ?? playlist.id,
                        title: playlist.title,
                        channelID: nil,
                        channelName: nil,
                        thumbnailURL: playlist.thumbnailURL,
                        videoCount: playlist.videoCount,
                        descriptionText: playlist.descriptionText,
                        isOwnedByUser: false
                    ))
                }
        }
    }

    private func remoteURL(for playlist: LocalPlaylistSnapshot) -> URL? {
        guard let sourceID = playlist.sourcePlaylistID else { return nil }
        return Playlist(
            id: sourceID, title: playlist.title, channelID: nil, channelName: nil,
            thumbnailURL: playlist.thumbnailURL, videoCount: playlist.videoCount,
            descriptionText: playlist.descriptionText, isOwnedByUser: false
        ).youtubeURL
    }

    private func playlistRow(_ playlist: LocalPlaylistSnapshot, availableIDs: Set<String>) -> some View {
        let downloaded = playlist.sourcePlaylistID.flatMap { playlistDownloads.manifest(for: $0) }
        let downloadedCount = downloaded?.videos.reduce(0) {
            $0 + (availableIDs.contains($1.id) ? 1 : 0)
        } ?? 0
        return HStack(spacing: 12) {
            KFImage(playlist.thumbnailURL)
                .thumbnail(size: CGSize(width: 72, height: 44)) {
                    Image(systemName: "music.note.list").foregroundStyle(.secondary)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 44)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.title).lineLimit(1)
                Text("\(playlist.videoCount) \(playlist.videoCount == 1 ? "video" : "videos")")
                    .font(.caption).foregroundStyle(.secondary)
                if playlist.isHydratingMetadata {
                    ProgressView(
                        value: Double(playlist.metadataHydrationProcessed),
                        total: Double(max(playlist.metadataHydrationTotal, 1))
                    )
                    .progressViewStyle(.linear)
                    Text("Resolving \(playlist.metadataHydrationProcessed) of \(playlist.metadataHydrationTotal)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if playlist.metadataHydrationFailures > 0 {
                    Label(
                        "\(playlist.metadataHydrationFailures) unavailable",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let downloaded, downloadedCount > 0 {
                Image(systemName: downloadedCount == downloaded.videos.count && downloaded.isPrepared
                    ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(downloadedCount) of \(downloaded.videos.count) downloaded")
            }
        }
    }

    private var personalPlaylists: [LocalPlaylistSnapshot] {
        playlists.filter { !$0.isSavedFromYouTube }
    }

    private var savedPlaylists: [LocalPlaylistSnapshot] {
        playlists.filter(\.isSavedFromYouTube)
    }

    private func movePlaylists(
        in items: [LocalPlaylistSnapshot],
        from source: IndexSet,
        to destination: Int,
        savedFromYouTube: Bool
    ) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        let personal = savedFromYouTube ? personalPlaylists : reordered
        let saved = savedFromYouTube ? reordered : savedPlaylists
        playlists = personal + saved
        Task { await service.reorderPlaylists(playlists.map(\.id)) }
    }

    private func deleteSelectedPlaylists() async {
        await service.delete(ids: selectedPlaylistIDs)
        selectedPlaylistIDs.removeAll()
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) { editMode = .inactive }
        await reload()
    }

    private func beginEditing() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            selectedPlaylistIDs.removeAll()
            editMode = .active
        }
    }

    private func finishEditing() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            editMode = .inactive
            selectedPlaylistIDs.removeAll()
        }
    }
}
