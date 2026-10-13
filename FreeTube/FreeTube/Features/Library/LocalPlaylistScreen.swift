import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

@available(iOS 17.0, *)
struct LocalPlaylistScreen: View {
    private enum EditingMode {
        case playlist
    }

    private enum CustomRange: String, Identifiable {
        case uploaded, length, views

        var id: String { rawValue }
    }

    let playlistID: String
    @State private var details: LocalPlaylistDetails?
    @State private var blocklist = VideoBlocklist.shared
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
    @State private var showingArtworkPicker = false
    @State private var selectedArtworkItem: PhotosPickerItem?
    @State private var artworkError: String?
    @State private var searchText = ""
    @State private var videoSort: LocalPlaylistVideoSort = .custom
    @State private var videoFilters = SearchVideoFilters()
    @State private var watchStatuses: [String: WatchHistoryStatus] = [:]
    @State private var customRange: CustomRange?
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let service = LocalPlaylistService()

    init(playlistID: String, initialSearchText: String = "") {
        self.playlistID = playlistID
        _searchText = State(initialValue: initialSearchText)
    }

    var body: some View {
        playlistDialogs
    }

    private var playlistList: some View {
        List(selection: editingMode != nil ? $selectedVideoIDs : nil) {
            if let details {
                Section {
                    playlistHeader(details)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(visibleVideos(in: details)) { video in
                    playlistVideoRow(video, in: details)
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
    }

    private var styledPlaylist: some View {
        playlistList
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(.container, edges: details == nil ? [] : .top)
        .background(MediaStyle.pageBackground)
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
    }

    private var livePlaylist: some View {
        styledPlaylist
        .toolbarBackground(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
        .overlay {
            emptyStateOverlay
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await reload() }
        }
        .task(id: details?.videos.map(\.id).joined(separator: ",")) {
            await refreshWatchStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            Task { await refreshWatchStatuses() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarButtons
            }
        }
    }

    private var playlistPresentations: some View {
        livePlaylist
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
        .photosPicker(isPresented: $showingArtworkPicker, selection: $selectedArtworkItem, matching: .images)
        .onChange(of: selectedArtworkItem) { _, item in
            guard let item else { return }
            Task { await updateArtwork(from: item) }
        }
        .sheet(item: $customRange) { range in
            switch range {
            case .uploaded:
                SearchDateRangeSheet(range: videoFilters.customUploadedRange) { selected in
                    videoFilters.customUploadedRange = selected
                    videoFilters.uploaded = .custom
                }
            case .length:
                SearchNumericRangeSheet(
                    title: "Duration Range", unit: "Minutes", range: videoFilters.customLengthRange
                ) { selected in
                    videoFilters.customLengthRange = selected
                    videoFilters.length = .custom
                }
            case .views:
                SearchNumericRangeSheet(
                    title: "View Count Range", unit: "Views", range: videoFilters.customViewsRange
                ) { selected in
                    videoFilters.customViewsRange = selected
                    videoFilters.views = .custom
                }
            }
        }
        .fileExporter(
            isPresented: $showingPlaylistExporter,
            document: playlistExportDocument,
            contentType: .json,
            defaultFilename: "FreeTube Playlist"
        ) { result in
            if case .failure(let error) = result { playlistExportError = error.localizedDescription }
        }
    }

    private var playlistDialogs: some View {
        playlistPresentations
        .alert("Couldn’t Export Playlist", isPresented: Binding(
            get: { playlistExportError != nil },
            set: { if !$0 { playlistExportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playlistExportError ?? "")
        }
        .alert("Couldn’t Use Photo", isPresented: Binding(
            get: { artworkError != nil },
            set: { if !$0 { artworkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(artworkError ?? "")
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

    @ViewBuilder
    private var emptyStateOverlay: some View {
        if let details, details.videos.isEmpty {
            ContentUnavailableView("Empty Playlist", systemImage: "music.note.list")
                .allowsHitTesting(false)
        } else if let details, editingMode == nil, searchText.isEmpty, videoFilters.isActive,
                  visibleVideos(in: details).isEmpty {
            ContentUnavailableView(
                "No matching videos", systemImage: "line.3.horizontal.decrease",
                description: Text("Try changing the playlist filters.")
            )
            .allowsHitTesting(false)
        } else if let details, editingMode == nil, searchText.isEmpty,
                  visibleVideos(in: details).isEmpty {
            ContentUnavailableView(
                "Playlist Videos Hidden",
                systemImage: "hand.raised",
                description: Text("Change blocked content in Settings to see them again.")
            )
            .allowsHitTesting(false)
        } else if let details, !searchText.isEmpty, visibleVideos(in: details).isEmpty {
            ContentUnavailableView.search(text: searchText)
                .allowsHitTesting(false)
        } else if hasLoaded && details == nil {
            ContentUnavailableView("Playlist Unavailable", systemImage: "music.note.list")
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        if editingMode != nil {
            Button(role: .destructive) {
                showingVideoDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedVideoIDs.isEmpty)
            Button("Done") { finishEditing() }
        } else {
            if details?.playlist.isSavedFromYouTube == false {
                Button {
                    showingAddVideo = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Video")
            }
            if let details {
                playlistFilterMenu
                localMoreMenu(details)
            }
        }
    }

    private func playlistVideoRow(_ video: Video, in details: LocalPlaylistDetails) -> some View {
        let accessory: VideoRow.Accessory = editingMode == nil
            ? .actions(offersPlayNext: true) : .reserved
        return VideoRow(video: video, accessory: accessory, onTap: {
            if editingMode != nil {
                if selectedVideoIDs.contains(video.id) {
                    selectedVideoIDs.remove(video.id)
                } else {
                    selectedVideoIDs.insert(video.id)
                }
            } else {
                player.loadPlaylist(playbackDetails(for: details), startAt: video, origin: .local)
            }
        })
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

    private func visibleVideos(in details: LocalPlaylistDetails) -> [Video] {
        // Edit mode must retain the source order so native move offsets still map to storage.
        if editingMode != nil { return details.videos }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return videoSort.ordered(details.videos).filter { video in
            !blocklist.blocks(video)
                && videoFilters.includes(video, status: watchStatuses[video.id], now: .now)
                && (query.isEmpty || video.title.localizedStandardContains(query)
                    || video.channelName.localizedStandardContains(query)
                    || video.id.localizedStandardContains(query))
        }
    }

    private func playbackDetails(for local: LocalPlaylistDetails) -> PlaylistDetails {
        let original = local.playbackDetails
        return PlaylistDetails(
            playlist: original.playlist,
            videos: videoSort.ordered(original.videos),
            continuationToken: original.continuationToken
        )
    }

    private func reload() async {
        let loaded = await service.details(id: playlistID)
        guard !Task.isCancelled else { return }
        details = loaded
        hasLoaded = true
    }

    private func refreshWatchStatuses() async {
        guard let details else { return }
        let ids = details.videos.map(\.id)
        let summary = await PersistenceWriter.shared.watchHistorySummary(videoIDs: ids)
        guard self.details?.videos.map(\.id) == ids else { return }
        watchStatuses = summary.statuses
    }

    private func playlistHeader(_ local: LocalPlaylistDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PlaylistArtworkHeader(
                thumbnailURL: local.playlist.thumbnailURL,
                imageData: local.playlist.customArtworkData
            ) {
                localActionToolbar(local)
            }
            PlaylistMetadataBlock(details: local.playbackDetails, isExpanded: $isDetailsExpanded)
            metadataRefreshStatus(for: local.playlist)
        }
        .padding(.top, PlayerLayoutMetrics.safeAreaInsets.top)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func metadataRefreshStatus(for playlist: LocalPlaylistSnapshot) -> some View {
        if playlist.isRefreshingMetadata {
            ProgressView(
                value: Double(playlist.metadataRefreshProcessed),
                total: Double(playlist.metadataRefreshTotal)
            )
            .tint(.white)
            .accessibilityLabel("Refreshing video details")
            .accessibilityValue("\(playlist.metadataRefreshProcessed) of \(playlist.metadataRefreshTotal)")
            .padding(.horizontal)
        } else if playlist.metadataRefreshFailures > 0 {
            Text("\(playlist.metadataRefreshFailures) videos could not be refreshed. Saved details were kept.")
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private func localActionToolbar(_ local: LocalPlaylistDetails) -> some View {
        HStack(spacing: 10) {
            PlaylistHeaderActionButton(title: "Play all", systemImage: "play.fill") {
                let playback = playbackDetails(for: local)
                guard let first = playback.videos.first(where: { !blocklist.blocks($0) }) else { return }
                player.loadPlaylist(playback, startAt: first, origin: .local)
            }
            .disabled(!local.videos.contains(where: { !blocklist.blocks($0) }) || editingMode != nil)
            PlaylistHeaderActionButton(title: "Shuffle", systemImage: "shuffle") {
                guard let random = local.videos.filter({ !blocklist.blocks($0) }).randomElement() else { return }
                player.loadPlaylist(playbackDetails(for: local), startAt: random, shuffled: true, origin: .local)
            }
            .disabled(!local.videos.contains(where: { !blocklist.blocks($0) }) || editingMode != nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    private func localMoreMenu(_ local: LocalPlaylistDetails) -> some View {
        Menu {
            Button {
                beginEditing()
            } label: {
                Label("Edit Playlist", systemImage: "list.bullet")
            }
            Button {
                showingEditor = true
            } label: {
                Label("Edit Details", systemImage: "square.and.pencil")
            }
            Button {
                showingArtworkPicker = true
            } label: {
                Label("Choose Playlist Banner", systemImage: "photo")
            }
            if local.playlist.customArtworkData != nil {
                Button {
                    Task {
                        await service.setArtwork(id: playlistID, data: nil)
                        await reload()
                    }
                } label: {
                    Label("Use Video Thumbnail", systemImage: "photo.on.rectangle")
                }
            }
            Button {
                Task { await exportPlaylist() }
            } label: {
                Label("Export Playlist", systemImage: "square.and.arrow.up")
            }
            if let share = TemporaryYouTubePlaylistShare.make(videoIDs: local.videos.map(\.id)) {
                ShareLink(item: share.url) {
                    if share.availableCount > share.includedCount {
                        Label("Share first 50 videos on YouTube", systemImage: "link")
                    } else {
                        Label("Share as YouTube playlist", systemImage: "link")
                    }
                }
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
                .disabled(local.playlist.isRefreshingMetadata)
            }
            Button {
                Task {
                    _ = await LocalPlaylistRefreshCoordinator.shared.schedule(playlistID: playlistID)
                    await reload()
                }
            } label: {
                Label("Refresh video details", systemImage: "arrow.clockwise")
            }
            .disabled(local.playlist.isRefreshingMetadata
                || local.playlist.isHydratingMetadata || local.videos.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(showsNavigationTitle || !searchText.isEmpty ? Color.primary : Color.white)
        }
        .accessibilityLabel("More playlist actions")
    }

    private var playlistFilterMenu: some View {
        Menu {
            Menu("Sort by") {
                Picker("Sort videos", selection: $videoSort) {
                    ForEach(LocalPlaylistVideoSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            }
            Divider()
            Menu("Watch history") {
                Picker("Watch history", selection: $videoFilters.watch) {
                    ForEach(SearchVideoFilters.Watch.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Menu("Upload date") {
                ForEach(SearchVideoFilters.Uploaded.allCases) { option in
                    Button {
                        if option == .custom { customRange = .uploaded }
                        else { videoFilters.uploaded = option }
                    } label: {
                        if videoFilters.uploaded == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            }
            Menu("Length") {
                ForEach(SearchVideoFilters.Length.allCases) { option in
                    Button {
                        if option == .custom { customRange = .length }
                        else { videoFilters.length = option }
                    } label: {
                        if videoFilters.length == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            }
            Menu("Views") {
                ForEach(SearchVideoFilters.Views.allCases) { option in
                    Button {
                        if option == .custom { customRange = .views }
                        else { videoFilters.views = option }
                    } label: {
                        if videoFilters.views == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            }
            Divider()
            Button("Reset Filters") {
                videoFilters = SearchVideoFilters()
                videoSort = .custom
            }
            .disabled(!videoFilters.isActive && videoSort == .custom)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(showsNavigationTitle || !searchText.isEmpty ? Color.primary : Color.white)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if videoFilters.isActive || videoSort != .custom {
                        Circle().fill(showsNavigationTitle || !searchText.isEmpty ? Color.primary : Color.white)
                            .frame(width: 5, height: 5).padding(8)
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Filter playlist videos")
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

    private func updateArtwork(from item: PhotosPickerItem) async {
        defer {
            if selectedArtworkItem == item { selectedArtworkItem = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = await Task.detached(priority: .utility, operation: {
                      PlaylistArtworkImage.jpegData(from: data)
                  }).value else {
                artworkError = "This photo could not be opened. Choose another image."
                return
            }
            await service.setArtwork(id: playlistID, data: image)
            await reload()
        } catch {
            artworkError = error.localizedDescription
        }
    }

    private func beginEditing() {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            videoSort = .custom
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
