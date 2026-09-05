import SwiftUI
import UniformTypeIdentifiers
import Kingfisher

@available(iOS 17.0, *)
struct LocalPlaylistsScreen: View {
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var showingCreate = false
    @State private var showingImporter = false
    @State private var newTitle = ""
    @State private var errorMessage: String?
    private let service = LocalPlaylistService()

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink {
                    LocalPlaylistScreen(playlistID: playlist.id)
                } label: {
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
                        }
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { playlists.indices.contains($0) ? playlists[$0].id : nil }
                Task {
                    for id in ids { await service.delete(id: id) }
                    await reload()
                }
            }
        }
        .navigationTitle("Local Playlists")
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No local playlists",
                    systemImage: "music.note.list",
                    description: Text("Create a playlist or import YouTube Takeout CSV files.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingCreate = true } label: {
                        Label("New Playlist", systemImage: "plus")
                    }
                    Button { showingImporter = true } label: {
                        Label("Import CSV Files", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $showingCreate) {
            TextField("Playlist name", text: $newTitle)
            Button("Create") { Task { await create() } }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .alert("Couldn’t Import Playlist", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            Task { await importFiles(result) }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await reload() }
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

    private func importFiles(_ result: Result<[URL], Error>) async {
        do {
            var failedFiles = [String]()
            for url in try result.get() {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    _ = try await service.importCSV(data: data, filename: url.lastPathComponent)
                } catch {
                    failedFiles.append(url.lastPathComponent)
                }
            }
            await reload()
            if !failedFiles.isEmpty {
                errorMessage = "Skipped files without a valid Video ID list: \(failedFiles.joined(separator: ", "))"
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
