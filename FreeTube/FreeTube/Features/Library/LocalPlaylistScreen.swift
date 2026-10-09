import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct LocalPlaylistScreen: View {
    private enum EditingMode {
        case playlist
    }

    let playlistID: String
    @State private var details: LocalPlaylistDetails?
    @State private var hasLoaded = false
    @State private var showsNavigationTitle = false
    @State private var isDetailsExpanded = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showingEditor = false
    @State private var showingAddVideo = false
    @State private var showingRestoreConfirmation = false
    @State private var editingMode: EditingMode?
    @State private var editMode: EditMode = .inactive
    @State private var selectedVideoIDs = Set<String>()
    @State private var showingVideoDeleteConfirmation = false
    @State private var showingPlaylistExporter = false
    @State private var playlistExportDocument = JSONDocument(data: Data())
    @State private var playlistExportError: String?
    @State private var searchText = ""
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let service = LocalPlaylistService()

    init(playlistID: String, initialSearchText: String = "") {
        self.playlistID = playlistID
        _searchText = State(initialValue: initialSearchText)
    }

    var body: some View {
        List(selection: $selectedVideoIDs) {
            if let details {
                Section {
                    playlistHeader(details)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(visibleVideos(in: details)) { video in
                    VideoRow(
                        video: video,
                        accessory: editingMode == nil
                            ? .actions(offersPlayNext: true)
                            : .reserved
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
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    guard editingMode != nil, searchText.isEmpty else { return }
                    Task {
                        await service.move(playlistID: playlistID, from: source, to: destination)
                        await reload()
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(.container, edges: details == nil ? [] : .top)
        .background(Color.black)
        .coordinateSpace(name: "playlistScroll")
        .onPreferenceChange(PlaylistTitlePositionKey.self) { titleBottom in
            guard titleBottom.isFinite else { return }
            showsNavigationTitle = titleBottom <= 0
        }
        .environment(\.editMode, $editMode)
        .initialContentLoading(hasLoaded: hasLoaded)
        .navigationTitle(showsNavigationTitle ? (details?.playlist.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search videos")
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty && editingMode != nil { finishEditing() }
        }
        .toolbarBackground(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
        .overlay {
            if let details, details.videos.isEmpty {
                ContentUnavailableView("Empty Playlist", systemImage: "music.note.list")
                    .allowsHitTesting(false)
            } else if let details, !searchText.isEmpty, visibleVideos(in: details).isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .allowsHitTesting(false)
            } else if hasLoaded && details == nil {
                ContentUnavailableView("Playlist Unavailable", systemImage: "music.note.list")
                    .allowsHitTesting(false)
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
                    if details?.playlist.isSavedFromYouTube == false {
                        Button {
                            showingAddVideo = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Video")
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
        .sheet(isPresented: $showingAddVideo) {
            AddVideoToPlaylistSheet(playlistID: playlistID)
        }
        .fileExporter(
            isPresented: $showingPlaylistExporter,
            document: playlistExportDocument,
            contentType: .json,
            defaultFilename: "FreeTube Playlist"
        ) { result in
            if case .failure(let error) = result { playlistExportError = error.localizedDescription }
        }
        .alert("Couldn’t Export Playlist", isPresented: Binding(
            get: { playlistExportError != nil },
            set: { if !$0 { playlistExportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playlistExportError ?? "")
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

    private func visibleVideos(in details: LocalPlaylistDetails) -> [Video] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return details.videos }
        return details.videos.filter {
            $0.title.localizedStandardContains(query)
                || $0.channelName.localizedStandardContains(query)
                || $0.id.localizedStandardContains(query)
        }
    }

    private func reload() async {
        let loaded = await service.details(id: playlistID)
        guard !Task.isCancelled else { return }
        details = loaded
        hasLoaded = true
    }

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
        VStack(alignment: .leading, spacing: 16) {
            PlaylistArtworkHeader(thumbnailURL: local.playlist.thumbnailURL) {
                localActionToolbar(local)
            }
            PlaylistMetadataBlock(details: playbackDetails(from: local), isExpanded: $isDetailsExpanded)
        }
        .padding(.top, PlayerLayoutMetrics.safeAreaInsets.top)
        .padding(.bottom, 16)
    }

    private func localActionToolbar(_ local: LocalPlaylistDetails) -> some View {
        HStack(spacing: 10) {
            PlaylistHeaderActionButton(title: "Play all", systemImage: "play.fill") {
                guard let first = local.videos.first else { return }
                player.loadPlaylist(playbackDetails(from: local), startAt: first)
            }
            .disabled(local.videos.isEmpty || editingMode != nil)
            PlaylistHeaderActionButton(title: "Shuffle", systemImage: "shuffle") {
                guard let random = local.videos.randomElement() else { return }
                player.loadPlaylist(playbackDetails(from: local), startAt: random, shuffled: true)
            }
            .disabled(local.videos.isEmpty || editingMode != nil)
            Spacer(minLength: 0)
            if editingMode == nil { localMoreMenu(local) }
        }
        .padding(.horizontal)
    }

    private func localMoreMenu(_ local: LocalPlaylistDetails) -> some View {
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
            Button {
                Task { await exportPlaylist() }
            } label: {
                Label("Export Playlist", systemImage: "square.and.arrow.up")
            }
            if local.playlist.isSavedFromYouTube {
                Button {
                    showingRestoreConfirmation = true
                } label: {
                    Label("Restore from YouTube", systemImage: "arrow.clockwise")
                }
                .disabled(isRestoring)
            }
            if local.playlist.metadataHydrationFailures > 0 {
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
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More playlist actions")
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

    private func exportPlaylist() async {
        do {
            let archiveService = PlaylistArchiveService()
            let archive = try await archiveService.makeArchive(playlistID: playlistID)
            playlistExportDocument = JSONDocument(data: try archiveService.encode(archive))
            showingPlaylistExporter = true
        } catch {
            playlistExportError = error.localizedDescription
        }
    }

    private func beginEditing() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            selectedVideoIDs.removeAll()
            editingMode = .playlist
            editMode = .active
        }
    }

    private func finishEditing() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
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
