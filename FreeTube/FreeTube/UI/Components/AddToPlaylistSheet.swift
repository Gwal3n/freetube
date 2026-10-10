import SwiftUI

/// Device-local Save sheet for a video's current moment or local playlists, and for queue saving.
@available(iOS 17.0, *)
struct AddToPlaylistSheet: View {
    let videos: [Video]
    let savesQueue: Bool
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [LocalPlaylistSnapshot] = []
    @State private var containingIDs = Set<String>()
    @State private var pendingPlaylistIDs = Set<String>()
    @State private var newTitle = ""
    @State private var isCreating = false
    @State private var isSavingNewPlaylist = false
    @State private var isLoading = true
    @State private var showsSavedMomentNotice = false
    @State private var savedMomentNoticeGeneration = 0
    @State private var savedMomentFeedbackCount = 0
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let service = LocalPlaylistService()

    init(video: Video) {
        videos = [video]
        savesQueue = false
    }

    init(queueVideos: [Video]) {
        videos = queueVideos
        savesQueue = true
    }

    var body: some View {
        NavigationStack {
            List {
                if canSaveCurrentMoment {
                    Section {
                        Button(action: saveCurrentMoment) {
                            Label("Save current moment", systemImage: "bookmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

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
                        .disabled(savesQueue && hasPendingWrites)
                    }
                }

                playlistSection("Personal", playlists: personalPlaylists)
            }
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isCreating)
            .navigationTitle(savesQueue ? "Save queue" : "Save")
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
        .overlay(alignment: .bottom) {
            if showsSavedMomentNotice {
                TransientNoticePill(title: Text("Moment saved"), systemImage: "checkmark", onUndo: nil)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : InterfaceMotion.notice, value: showsSavedMomentNotice)
        .sensoryFeedback(.success, trigger: savedMomentFeedbackCount)
    }

    private var canSaveCurrentMoment: Bool {
        guard !savesQueue, let video = videos.first else { return false }
        return !video.isLive && player.currentVideo?.id == video.id
            && video.youtubeShareURL(at: 0) != nil
    }

    private func saveCurrentMoment() {
        guard canSaveCurrentMoment, let video = videos.first,
              SavedMomentStore.shared.add(video: video, time: player.elapsed) != nil else { return }
        savedMomentFeedbackCount &+= 1
        savedMomentNoticeGeneration &+= 1
        let generation = savedMomentNoticeGeneration
        withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
            showsSavedMomentNotice = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard savedMomentNoticeGeneration == generation else { return }
            withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
                showsSavedMomentNotice = false
            }
        }
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
                    Button { Task { await saveOrToggle(playlist.id) } } label: {
                        HStack {
                            Text(playlist.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: savesQueue ? "plus.circle" :
                                (containingIDs.contains(playlist.id) ? "checkmark.circle.fill" : "plus.circle"))
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
                    .disabled(savesQueue ? hasPendingWrites : pendingPlaylistIDs.contains(playlist.id))
                    .accessibilityValue(savesQueue ? "Add queue" :
                        (containingIDs.contains(playlist.id) ? "Saved" : "Not saved"))
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
        guard !savesQueue, let video = videos.first else { return }
        var ids = Set<String>()
        for playlist in playlists {
            if await service.contains(videoID: video.id, playlistID: playlist.id) {
                ids.insert(playlist.id)
            }
        }
        containingIDs = ids
    }

    private func saveOrToggle(_ playlistID: String) async {
        if savesQueue {
            guard !hasPendingWrites else { return }
            pendingPlaylistIDs.insert(playlistID)
            await service.append(videos: videos, to: playlistID)
            pendingPlaylistIDs.remove(playlistID)
            dismiss()
        } else {
            await toggle(playlistID)
        }
    }

    private func toggle(_ playlistID: String) async {
        guard let video = videos.first else { return }
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
        guard !title.isEmpty, !hasPendingWrites else { return }
        isSavingNewPlaylist = true
        defer { isSavingNewPlaylist = false }
        let id = await service.create(title: title)
        if savesQueue {
            await service.append(videos: videos, to: id)
            dismiss()
            return
        }
        if let video = videos.first { await service.add(video: video, to: id) }
        newTitle = ""
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            isCreating = false
        }
        await reload()
    }
}
