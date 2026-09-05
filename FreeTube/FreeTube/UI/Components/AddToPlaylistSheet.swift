import SwiftUI

/// Device-local playlist picker used everywhere a video exposes Save.
@available(iOS 17.0, *)
struct AddToPlaylistSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var containingIDs = Set<String>()
    @State private var newTitle = ""
    @State private var isCreating = false
    private let service = LocalPlaylistService()

    var body: some View {
        NavigationStack {
            List {
                if isCreating {
                    Section("New Playlist") {
                        TextField("Playlist name", text: $newTitle)
                        Button("Create and Save") { Task { await createAndSave() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section {
                        Button { withAnimation { isCreating = true } } label: {
                            Label("Create New Playlist", systemImage: "plus.circle.fill")
                        }
                    }
                }

                Section("Local Playlists") {
                    if playlists.isEmpty {
                        Text("No local playlists yet.").foregroundStyle(.secondary)
                    }
                    ForEach(playlists) { playlist in
                        Button { Task { await save(to: playlist.id) } } label: {
                            HStack {
                                Text(playlist.title).foregroundStyle(.primary)
                                Spacer()
                                if containingIDs.contains(playlist.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Text("\(playlist.videoCount)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(containingIDs.contains(playlist.id))
                    }
                }
            }
            .navigationTitle("Save to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func reload() async {
        playlists = await service.playlists()
        var ids = Set<String>()
        for playlist in playlists {
            if await service.contains(videoID: video.id, playlistID: playlist.id) {
                ids.insert(playlist.id)
            }
        }
        containingIDs = ids
    }

    private func save(to playlistID: String) async {
        await service.add(video: video, to: playlistID)
        containingIDs.insert(playlistID)
        playlists = await service.playlists()
    }

    private func createAndSave() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let id = await service.create(title: title)
        await service.add(video: video, to: id)
        newTitle = ""
        isCreating = false
        await reload()
    }
}
