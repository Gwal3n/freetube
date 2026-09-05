import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct LocalPlaylistsScreen: View {
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var showingCreate = false
    @State private var newTitle = ""
    @State private var editMode: EditMode = .inactive
    @State private var selectedPlaylistIDs = Set<String>()
    @State private var showingDeleteConfirmation = false
    private let service = LocalPlaylistService()

    var body: some View {
        List(selection: $selectedPlaylistIDs) {
            playlistSection("Personal", items: personalPlaylists, savedFromYouTube: false)
            playlistSection("Saved from YouTube", items: savedPlaylists, savedFromYouTube: true)
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Local Playlists")
        .overlay {
            if playlists.isEmpty {
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
                }
                EditButton()
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedPlaylistIDs.isEmpty)
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
        .onChange(of: editMode) { _, mode in
            if !mode.isEditing { selectedPlaylistIDs.removeAll() }
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
    }

    private func reload() async { playlists = await service.playlists() }

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
                ForEach(items) { playlist in
                    NavigationLink {
                        LocalPlaylistScreen(playlistID: playlist.id)
                    } label: {
                        playlistRow(playlist)
                    }
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

    private func playlistRow(_ playlist: LocalPlaylistSnapshot) -> some View {
        HStack(spacing: 12) {
            KFImage(playlist.thumbnailURL)
                .placeholder { Image(systemName: "music.note.list").foregroundStyle(.secondary) }
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
        withAnimation { editMode = .inactive }
        await reload()
    }
}
