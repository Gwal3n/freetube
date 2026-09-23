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
    @State private var isSavingNewPlaylist = false
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
                                if isSavingNewPlaylist {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNewPlaylist)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Section {
                        Button {
                            withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
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
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isCreating)
            .navigationTitle("Save to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(hasPendingWrites)
                }
            }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasPendingWrites)
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
                            Image(systemName: containingIDs.contains(playlist.id) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(
                                    reduceMotion ? nil : InterfaceMotion.quick,
                                    value: containingIDs.contains(playlist.id)
                                )
                                .opacity(pendingPlaylistIDs.contains(playlist.id) ? 0.65 : 1)
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

    private var hasPendingWrites: Bool {
        isSavingNewPlaylist || !pendingPlaylistIDs.isEmpty
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
        if containingIDs.contains(playlistID) {
            await service.remove(videoID: video.id, from: playlistID)
            withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                containingIDs.remove(playlistID)
                pendingPlaylistIDs.remove(playlistID)
            }
        } else {
            await service.add(video: video, to: playlistID)
            withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                containingIDs.insert(playlistID)
                pendingPlaylistIDs.remove(playlistID)
            }
        }
    }

    private func createAndSave() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isSavingNewPlaylist else { return }
        isSavingNewPlaylist = true
        defer { isSavingNewPlaylist = false }
        let id = await service.create(title: title)
        await service.add(video: video, to: id)
        newTitle = ""
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            isCreating = false
        }
        await reload()
    }
}
