import SwiftUI
import AVFoundation
import UIKit

@available(iOS 17.0, *)
struct DownloadsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var model = DownloadsViewModel()
    /// File-system + xattr backed downloads list. Replaces the SwiftData `@Query` —
    /// the store rebuilds `entries` from the Documents root on launch and after every
    /// `DownloadsStore.didChange` notification (posted by the download writers).
    @State private var store = DownloadsStore.shared
    @State private var blocklist = VideoBlocklist.shared
    @State private var playlistDownloads = PlaylistDownloadCoordinator.shared
    @Environment(PlayerStateManager.self) private var player
    @State private var path: [AppNavigationRequest.Destination] = []

    // MARK: - Selection + sort state

    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var sortBy: SortBy = .date
    @State private var sortDescending = true
    @State private var searchText = ""
    /// Confirmation alert before deleting selected items in selection mode.
    @State private var showBulkDeleteConfirmation = false
    /// When non-nil, the user tapped delete on a single row — confirm before removing.
    @State private var pendingSingleDelete: SavedItem?
    @State private var pendingPlaylistRemovalID: String?
    /// When non-nil, the user tapped "Open in…" on a row — present the system activity sheet.
    @State private var shareFileURL: URL?
    @State private var exportFileURL: URL?
    @State private var showsPhotosSavedNotice = false

    /// What the user can sort by. `duration` reads each file's AVAsset at row-build time —
    /// inexpensive because we already cached it once per launch.
    enum SortBy: String, CaseIterable, Identifiable {
        case date = "Date downloaded"
        case title = "Title"
        case size = "File size"
        case duration = "Duration"
        var id: String { rawValue }
    }

    private var sortLabel: String {
        switch sortBy {
        case .date: return sortDescending ? String(localized: "Newest") : String(localized: "Oldest")
        case .title: return sortDescending ? "Z–A" : "A–Z"
        case .size: return sortDescending ? String(localized: "Largest") : String(localized: "Smallest")
        case .duration: return sortDescending ? String(localized: "Longest") : String(localized: "Shortest")
        }
    }

    /// Active in-flight downloads.
    private var inProgress: [DownloadTaskSnapshot] {
        model.manager.activeTasks.filter { snapshot in
            guard !blocklist.blocks(title: snapshot.title, channelID: nil, channelName: nil) else { return false }
            guard !playlistMemberIDs.contains(snapshot.videoID) else { return false }
            guard matchesSearch(snapshot.title, snapshot.videoID) else { return false }
            switch snapshot.state {
            case .queued, .downloading, .paused, .failed: return true
            case .completed: return false
            }
        }
    }

    /// File-system + xattr backed list. `DownloadsStore.entries` already includes both
    /// "tracked" rows (file has our metadata xattr) and "orphan" rows (file present but no
    /// xattr — surfaces with filename-as-title). We just map and apply the user's sort.
    private var savedItems: [SavedItem] {
        sortItems(store.entries
            .filter { entry in
                !playlistMemberIDs.contains(entry.videoID)
            }
            .map(SavedItem.init(from:))
            .filter { !blocklist.blocks(title: $0.title, channelID: nil, channelName: $0.channelName) }
            .filter { matchesSearch($0.title, $0.channelName, $0.videoID) })
    }

    private var visiblePlaylists: [PlaylistDownloadManifest] {
        playlistDownloads.manifests
            .filter { manifest in
                matchesSearch(manifest.title)
                    && !blocklist.blocks(title: manifest.title, channelID: nil, channelName: nil)
                    && manifest.videos.contains(where: { !blocklist.blocks($0) })
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesSearch(_ values: String...) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || values.contains { $0.localizedStandardContains(query) }
    }

    private var playlistMemberIDs: Set<String> { playlistDownloads.protectedVideoIDs }

    private var downloadedVideoIDs: Set<String> {
        Set(store.entries.map(\.videoID))
    }

    /// Count actual files once, even if a video belongs to several downloaded playlists.
    private var totalSize: Int64 { store.entries.reduce(0) { $0 + $1.fileSize } }
    private var totalCount: Int { store.entries.count }

    var body: some View {
        NavigationStack(path: $path) {
            List(selection: $selectedIDs) {
                if totalCount > 0 {
                    Section {
                        HStack {
                            Label("Downloaded media", systemImage: "internaldrive")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }

                if !inProgress.isEmpty {
                    Section {
                        ForEach(inProgress) { snapshot in
                            transferRow(snapshot)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text("Transfer queue")
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .symbolEffect(
                                    .pulse,
                                    options: reduceMotion ? .nonRepeating : .repeating,
                                    value: inProgress.count
                                )
                            Text(verbatim: "\(inProgress.count)")
                                .contentTransition(.numericText())
                        }
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                    }
                }

                if !visiblePlaylists.isEmpty {
                    Section("Playlists") {
                        let downloadedIDs = downloadedVideoIDs
                        ForEach(visiblePlaylists) { manifest in
                            let downloadedCount = manifest.videos.reduce(0) {
                                $0 + (downloadedIDs.contains($1.id) && !blocklist.blocks($1) ? 1 : 0)
                            }
                            DownloadedPlaylistRow(
                                manifest: manifest,
                                downloadedCount: downloadedCount,
                                currentVideoTitle: playlistDownloads.activePlaylistID == manifest.id
                                    ? manifest.videos.first(where: { $0.id == playlistDownloads.currentVideoID })?.title
                                    : nil,
                                currentVideoProgress: playlistDownloads.activePlaylistID == manifest.id
                                    ? model.manager.progressByVideoID[playlistDownloads.currentVideoID ?? ""] ?? 0
                                    : 0,
                                isRemoving: playlistDownloads.removingPlaylistIDs.contains(manifest.id),
                                onResume: { playlistDownloads.resume(manifest.id) },
                                onCancel: { playlistDownloads.cancel(manifest.id) }
                            )
                            .contextMenu {
                                if [.queued, .preparing, .downloading].contains(manifest.status) {
                                    Button {
                                        playlistDownloads.cancel(manifest.id)
                                    } label: {
                                        Label("Cancel playlist download", systemImage: "xmark.circle")
                                    }
                                } else if downloadedCount < manifest.videos.count || !manifest.isPrepared {
                                    Button {
                                        playlistDownloads.resume(manifest.id)
                                    } label: {
                                        Label("Resume playlist download", systemImage: "arrow.clockwise")
                                    }
                                }
                                Button(role: .destructive) {
                                    pendingPlaylistRemovalID = manifest.id
                                } label: {
                                    Label("Delete playlist and downloads", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingPlaylistRemovalID = manifest.id
                                } label: {
                                    Label("Delete playlist and downloads", systemImage: "trash")
                                }
                            }
                            .disabled(isSelecting || playlistDownloads.removingPlaylistIDs.contains(manifest.id))
                        }
                    }
                }

                if !savedItems.isEmpty || (!isSearching && playlistDownloads.manifests.isEmpty && inProgress.isEmpty) {
                    Section {
                        if savedItems.isEmpty && !isSearching {
                            if totalCount > 0 {
                                ContentUnavailableView(
                                    "Downloads Hidden",
                                    systemImage: "hand.raised",
                                    description: Text("Change blocked content in Settings to see saved files again.")
                                )
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                            } else {
                                ContentUnavailableView(
                                    "No Downloads",
                                    systemImage: "arrow.down.circle",
                                    description: Text("Download a video from the player or a link to watch it offline.")
                                )
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        }
                        ForEach(savedItems) { item in
                            savedItemRow(item)
                                .tag(item.id)
                        }
                    } header: {
                        savedHeader
                    }
                }

                if isSearching && inProgress.isEmpty && visiblePlaylists.isEmpty && savedItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search downloads")
            .onChange(of: searchText) { _, _ in
                selectedIDs.removeAll()
                isSelecting = false
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(isSelecting
                             ? String(localized: "\(selectedIDs.count) selected")
                             : String(localized: "Downloads"))
            .navigationDestination(for: AppNavigationRequest.Destination.self) { destination in
                switch destination {
                case .channel(let id): ChannelScreen(channelID: id)
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
            // Glass-style action bar with just two pill buttons: Select all + Delete.
            .safeAreaInset(edge: .top) {
                if isSelecting {
                    selectionActionBar
                }
            }
            .alert(
                "Delete \(selectedIDs.count) \(selectedIDs.count == 1 ? "video" : "videos")?",
                isPresented: $showBulkDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the selected file\(selectedIDs.count == 1 ? "" : "s") from your device.")
            }
            .alert(
                "Delete this video?",
                isPresented: Binding(
                    get: { pendingSingleDelete != nil },
                    set: { if !$0 { pendingSingleDelete = nil } }
                ),
                presenting: pendingSingleDelete
            ) { item in
                Button("Delete", role: .destructive) {
                    deleteSavedItem(item)
                    pendingSingleDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingSingleDelete = nil }
            } message: { item in
                Text("“\(item.title)” will be permanently removed from your device.")
            }
            .confirmationDialog(
                "Remove downloaded playlist?",
                isPresented: Binding(
                    get: { pendingPlaylistRemovalID != nil },
                    set: { if !$0 { pendingPlaylistRemovalID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Playlist and Downloads", role: .destructive) {
                    if let id = pendingPlaylistRemovalID {
                        Task {
                            let wasRemoved = await playlistDownloads.remove(id)
                            if !wasRemoved {
                                model.errorState = ErrorState(message: "Some playlist files couldn't be removed. Try again.")
                            }
                        }
                    }
                    pendingPlaylistRemovalID = nil
                }
                Button("Cancel", role: .cancel) { pendingPlaylistRemovalID = nil }
            } message: {
                Text("Downloaded videos in this playlist will be deleted from this device. Files also used by another downloaded playlist will be kept.")
            }
            .errorToast(Bindable(model).errorState)
            .overlay(alignment: .bottom) {
                if showsPhotosSavedNotice {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Presents UIActivityViewController for the per-row "Open in…" action. The bound bool
            // mirrors `shareFileURL` so the sheet lifecycle matches user intent.
            .sheet(isPresented: Binding(
                get: { shareFileURL != nil },
                set: { if !$0 { shareFileURL = nil } }
            )) {
                if let url = shareFileURL {
                    ActivityShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: Binding(
                get: { exportFileURL != nil },
                set: { if !$0 { exportFileURL = nil } }
            )) {
                if let url = exportFileURL {
                    DownloadedFileExportPicker(fileURL: url) { exportFileURL = nil }
                }
            }
            .onChange(of: navigationRouter.downloads?.id, initial: true) { _, _ in
                guard let request = navigationRouter.downloads else { return }
                navigationRouter.downloads = nil
                AppLog(subsystem: "com.leshko.freetube", category: "Navigation")
                    .info("Downloads received player destination")
                path.append(request.destination)
            }
        }
    }

    // MARK: - Saved section header (stats + sort)

    @ViewBuilder
    private var savedHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved on device").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !savedItems.isEmpty {
                    Text(verbatim: "\(savedItems.count) \(savedItems.count == 1 ? "video" : "videos")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !savedItems.isEmpty {
                if !isSelecting {
                    Menu {
                        ForEach(SortBy.allCases) { option in
                            Button {
                                if sortBy == option {
                                    sortDescending.toggle()
                                } else {
                                    sortBy = option
                                    sortDescending = option == .date || option == .size
                                }
                            } label: {
                                if sortBy == option {
                                    Label(option.rawValue, systemImage: sortDescending ? "arrow.down" : "arrow.up")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label(sortLabel, systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Sort saved videos")
                }
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    selectedIDs.removeAll()
                }
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .textCase(nil)
        .tint(.white)
    }

    // MARK: - Transfer rows (in-progress)

    @ViewBuilder
    private func transferRow(_ snapshot: DownloadTaskSnapshot) -> some View {
        DownloadTransferRow(snapshot: snapshot) {
            withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                model.cancel(snapshot)
            }
        } onRetry: {
            Task { await model.retry(snapshot) }
        }
        .swipeActions {
            if case .failed = snapshot.state {
                Button("Dismiss", role: .destructive) { model.cancel(snapshot) }
            }
        }
    }

    // MARK: - Downloaded row + per-row menu

    @ViewBuilder
    private func savedItemRow(_ item: SavedItem) -> some View {
        let row = DownloadedVideoRow(
            item: item,
            isSelecting: isSelecting,
            onPlay: { playLocal(item) },
            onDelete: { pendingSingleDelete = item }
        ) {
            rowMenu(item).buttonStyle(.plain)
        }
        if isSelecting {
            row.listRowBackground(Color.clear)
        } else {
            row.contextMenu {
                Button { playLocal(item) } label: {
                    Label("Play downloaded video", systemImage: "play.fill")
                }
                rowActions(item)
            } preview: {
                DownloadedVideoContextPreview(item: item)
            }
            .listRowBackground(Color.clear)
        }
    }

    private func rowMenu(_ item: SavedItem) -> some View {
        Menu {
            rowActions(item)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .padding(.horizontal, 8)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func rowActions(_ item: SavedItem) -> some View {
        Button {
            Task { await saveToPhotos(item) }
        } label: {
            Label("Save to Photos", systemImage: "photo.on.rectangle")
        }
        .disabled(model.isSavingToPhotos)
        Button {
            exportFileURL = item.fileURL
        } label: {
            Label("Save to Files", systemImage: "folder")
        }
        // System "Open in…" share sheet for the downloaded mp4 — opens UIActivityViewController
        // with the local file URL so the user can send it to VLC, Files, AirDrop, etc. We use
        // a Button + sheet rather than `ShareLink` because the latter is unreliable for
        // `file://` URLs inside a `Menu` (it sometimes serializes them as plain text).
        Button {
            shareFileURL = item.fileURL
        } label: {
            Label("Open in…", systemImage: "square.and.arrow.up")
        }
        // "Show in Finder" only renders on macOS runtimes (Designed-for-iPad-on-Mac
        // or real Catalyst). On iPhone/iPad the Files app doesn't accept "select this
        // specific file" deeplinks, so the item is hidden there — surfacing a dead
        // menu entry would just confuse the user.
        if MacIntegration.isRunningOnMac {
            Button {
                MacIntegration.revealInFinder(item.fileURL)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        Divider()
        Button(role: .destructive) {
            pendingSingleDelete = item
        } label: {
            Label("Delete from downloaded", systemImage: "trash")
        }
    }

    /// Top-of-screen action bar in selection mode. Two glass-style pill buttons: Select all on the
    /// left, Delete on the right. The selected count lives in the nav title as a subtitle.
    @ViewBuilder
    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            glassButton(
                title: selectedIDs.count == savedItems.count ? "Deselect all" : "Select all",
                systemImage: selectedIDs.count == savedItems.count ? "checklist.unchecked" : "checklist",
                role: nil
            ) {
                if selectedIDs.count == savedItems.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(savedItems.map(\.id))
                }
            }

            Spacer()

            glassButton(
                title: "Delete",
                systemImage: "trash",
                role: .destructive
            ) {
                showBulkDeleteConfirmation = true
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Pill button with a translucent material backdrop — the closest we get to iOS 18's `.glassEffect`
    /// while still supporting iOS 17. Destructive buttons get a red tint, neutral buttons inherit
    /// the accent color.
    @ViewBuilder
    private func glassButton(title: String, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort

    private func sortItems(_ items: [SavedItem]) -> [SavedItem] {
        let ordered: [SavedItem]
        switch sortBy {
        case .date:
            ordered = items.sorted { $0.modifiedAt < $1.modifiedAt }
        case .title:
            ordered = items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .size:
            ordered = items.sorted { $0.fileSize < $1.fileSize }
        case .duration:
            ordered = items.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
        return sortDescending ? ordered.reversed() : ordered
    }

    // MARK: - Actions

    private func deleteSavedItem(_ item: SavedItem) {
        // `DownloadsStore.delete` removes the file (xattrs go with it) and posts the
        // change notification so the store reloads. No SwiftData row to delete.
        DownloadsStore.shared.delete(at: item.fileURL)
        selectedIDs.remove(item.id)
    }

    private func deleteSelected() {
        let items = savedItems.filter { selectedIDs.contains($0.id) }
        for item in items {
            deleteSavedItem(item)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    // MARK: - Helpers

    private func playLocal(_ item: SavedItem) {
        if item.isFromURL {
            // URL-fetched items don't have a YouTube `videoID` the resolver could use, and
            // the file's already on disk — `loadLocalFile` plays it directly without going
            // through `ensureDownloaded`. The synthetic Video built inside that method
            // gives the mini-player/popup chrome everything it needs.
            player.loadLocalFile(
                at: item.fileURL,
                title: item.title,
                source: item.channelName.isEmpty ? nil : item.channelName,
                thumbnailURL: nil
            )
            return
        }
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            model.errorState = ErrorState(from: DownloadedVideoExportError.fileMissing)
            return
        }
        let video = Video(
            id: item.videoID,
            title: item.title,
            channelID: "",
            channelName: item.channelName,
            channelThumbnailURL: nil,
            thumbnailURL: nil,
            duration: item.duration,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
        // A Downloads-row tap is file-only: a missing or unreadable local item must not
        // silently switch to a remote stream or restart the download pipeline.
        player.load(video, localFileURL: item.fileURL)
    }

    private func saveToPhotos(_ item: SavedItem) async {
        guard await model.saveToPhotos(fileURL: item.fileURL) else { return }
        withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
            showsPhotosSavedNotice = true
        }
        try? await Task.sleep(for: .seconds(2))
        withAnimation(reduceMotion ? nil : InterfaceMotion.notice) {
            showsPhotosSavedNotice = false
        }
    }
}

/// Unified row data for the "Saved on device" section. Backed by `DownloadsStore`'s
/// per-file xattr metadata, with sensible fallbacks (filename-as-title) for files that
/// have no xattr (manually dropped into the Downloads folder, or written before the xattr
/// migration).
@available(iOS 17.0, *)
struct SavedItem: Identifiable {
    let id: String
    let videoID: String
    let title: String
    let channelName: String
    let fileURL: URL
    let fileSize: Int64
    let modifiedAt: Date
    let thumbnailData: Data?
    /// Read from AVURLAsset on construction. Sync (deprecated API but fine) so we can use it as a
    /// sort key without async plumbing.
    let duration: TimeInterval?
    /// `nil` for YouTube downloads (videoID alone reconstructs the canonical YouTube URL).
    /// Set to the original pasted URL for legacy Link downloads — drives
    /// the branch between `loadLocalFile` (URL items) and the YouTube resolver.
    let originalURL: String?

    /// Convenience flag: true when this row came from the former Link downloader. Drives tap and
    /// menu behavior in `DownloadsScreen` so we don't accidentally route an Instagram
    /// download through the YouTube resolver.
    var isFromURL: Bool { originalURL != nil }

    init(from entry: DownloadEntry) {
        let fallbackID = entry.fileURL.deletingPathExtension().lastPathComponent
        self.fileURL = entry.fileURL
        self.fileSize = entry.fileSize
        // Pre-resolved during the off-main scan — no sync `AVURLAsset` read here. With a
        // large library this was the dominant source of scroll lag (the row builder ran
        // per body re-evaluation, and `.duration.seconds` is a blocking moov-atom read).
        self.duration = entry.duration
        if let m = entry.metadata {
            self.id = m.videoID
            self.videoID = m.videoID
            self.title = m.title
            self.channelName = m.channelName
            self.modifiedAt = m.downloadedAt
            self.thumbnailData = m.thumbnailData
            self.originalURL = m.originalURL
        } else {
            // Orphan: file with no metadata xattr. Surface with filename as title so the
            // user can still identify and play it.
            self.id = fallbackID
            self.videoID = fallbackID
            self.title = fallbackID
            self.channelName = ""
            self.modifiedAt = entry.modifiedAt
            self.thumbnailData = nil
            self.originalURL = nil
        }
    }

}
