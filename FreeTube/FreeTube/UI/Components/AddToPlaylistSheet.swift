import SwiftUI

/// Device-local playlist picker used everywhere a video exposes Save.
@available(iOS 17.0, *)
struct AddToPlaylistSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var containingIDs = Set<String>()
    @State private var pendingPlaylistIDs = Set<String>()
    @State private var newTitle = ""
    @State private var isCreating = false
    @State private var isLoading = true
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let service = LocalPlaylistService()

    var body: some View {
        NavigationStack {
            List {
                if isCreating {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                            TextField("Playlist name", text: $newTitle)
                                .focused($titleFocused)
                                .submitLabel(.done)
                                .onSubmit { Task { await createAndSave() } }
                            Button {
                                Task { await createAndSave() }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Section {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                                isCreating = true
                            }
                            Task { @MainActor in
                                await Task.yield()
                                titleFocused = true
                            }
                        } label: {
                            Label("New playlist", systemImage: "plus.circle")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                playlistSection("Personal", playlists: personalPlaylists)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isCreating)
            .navigationTitle("Save to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func playlistSection(_ title: String, playlists: [LocalPlaylistSnapshot]) -> some View {
        if !playlists.isEmpty || title == "Personal" {
            Section(title) {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading playlists…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if playlists.isEmpty {
                    Text("No personal playlists yet.").foregroundStyle(.secondary)
                }
                ForEach(playlists) { playlist in
                    Button { Task { await toggle(playlist.id) } } label: {
                        HStack {
                            Text(playlist.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if pendingPlaylistIDs.contains(playlist.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: containingIDs.contains(playlist.id) ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .disabled(pendingPlaylistIDs.contains(playlist.id))
                    .accessibilityValue(containingIDs.contains(playlist.id) ? "Saved" : "Not saved")
                }
            }
        }
    }

    private var personalPlaylists: [LocalPlaylistSnapshot] {
        playlists.filter { !$0.isSavedFromYouTube }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        playlists = await service.playlists()
        var ids = Set<String>()
        for playlist in playlists {
            if await service.contains(videoID: video.id, playlistID: playlist.id) {
                ids.insert(playlist.id)
            }
        }
        containingIDs = ids
    }

    private func toggle(_ playlistID: String) async {
        guard !pendingPlaylistIDs.contains(playlistID) else { return }
        pendingPlaylistIDs.insert(playlistID)
        defer { pendingPlaylistIDs.remove(playlistID) }
        if containingIDs.contains(playlistID) {
            await service.remove(videoID: video.id, from: playlistID)
            containingIDs.remove(playlistID)
        } else {
            await service.add(video: video, to: playlistID)
            containingIDs.insert(playlistID)
        }
    }

    private func createAndSave() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let id = await service.create(title: title)
        await service.add(video: video, to: id)
        newTitle = ""
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            isCreating = false
        }
        await reload()
    }
}
