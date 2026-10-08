import SwiftUI

/// Playlist detail screen. Top-down layout:
///   1. Large playlist artwork with overlaid actions
///   2. Title + channel + video-count metadata
///   3. List of videos
///
/// Public YouTube playlists are read-only. Editing and reordering live exclusively in the local
/// playlist screens, keeping this view independent from account-only mutation endpoints.
@available(iOS 17.0, *)
struct PlaylistScreen: View {
    @State private var model: PlaylistViewModel
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSavedLocally = false
    @State private var isSavingLocally = false
    @State private var playlistDownloads = PlaylistDownloadCoordinator.shared
    @State private var downloads = DownloadsStore.shared
    private let localPlaylistService = LocalPlaylistService()

    /// True after the user taps "More" — expands the metadata block to show the full description
    /// and every available stat (view count + video count + creator). Collapsed by default so the
    /// header stays compact and the video list isn't pushed below the fold.
    @State private var isDetailsExpanded = false
    @State private var showsNavigationTitle = false
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @State private var playbackProgress: [String: Double] = [:]

    init(playlistID: String) {
        _model = State(wrappedValue: PlaylistViewModel(playlistID: playlistID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let details = model.details {
                    // The image begins below the status bar but fills the navigation-bar region.
                    // Metadata keeps the standard content inset below it.
                    VStack(alignment: .leading, spacing: 16) {
                        artworkHeader(details)
                        PlaylistMetadataBlock(details: details, isExpanded: $isDetailsExpanded)
                    }
                    .padding(.top, PlayerLayoutMetrics.safeAreaInsets.top)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    videosList(details)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                } else if model.isLoading {
                    playlistPlaceholder
                } else if model.errorState != nil {
                    ContentUnavailableView {
                        Label("Unable to Load Playlist", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try Again") { Task { await model.load() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .ignoresSafeArea(.container, edges: model.details == nil ? [] : .top)
        .background(Color.black)
        .coordinateSpace(name: "playlistScroll")
        .onPreferenceChange(PlaylistTitlePositionKey.self) { titleBottom in
            guard titleBottom.isFinite else { return }
            showsNavigationTitle = model.details != nil && titleBottom <= 0
        }
        .navigationTitle(showsNavigationTitle ? (model.details?.playlist.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        // Let artwork show through initially, then restore native bar material when the
        // scrolled-away playlist name becomes the compact navigation title.
        .toolbarBackground(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
        .task { await model.load() }
        .task(id: model.details?.playlist.id) {
            guard let id = model.details?.playlist.id else { return }
            isSavedLocally = await localPlaylistService.isRemoteSaved(id: id)
        }
        .task(id: "\(showHistoryProgressBars):" + (model.details?.videos.map(\.id).joined(separator: ",") ?? "")) {
            let ids = model.details?.videos.map(\.id) ?? []
            playbackProgress = showHistoryProgressBars
                ? await PersistenceWriter.shared.watchProgress(videoIDs: ids)
                : [:]
        }
        .errorToast(Bindable(model).errorState)
    }

    /// Reserves the loaded artwork, action row, metadata, and first video rows. Only opacity
    /// changes while loading, so the eventual content does not appear to slide into place.
    private var playlistPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle()
                .fill(MediaStyle.placeholderFill)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        ForEach([CGFloat(76), 72, 98], id: \.self) { width in
                            Capsule()
                                .fill(.quaternary)
                                .frame(maxWidth: width)
                                .frame(height: 36)
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(.quaternary)
                            .frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(maxWidth: 240)
                    .frame(height: 20)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 150, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 110, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 135, height: 10)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: MediaStyle.spacing) {
                        RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                            .fill(.quaternary)
                            .frame(
                                width: dynamicTypeSize.isAccessibilitySize ? 104 : 144,
                                height: dynamicTypeSize.isAccessibilitySize ? 58.5 : 81
                            )
                        VStack(alignment: .leading, spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                                .frame(maxWidth: 170)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 90, height: 9)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .modifier(SkeletonPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading playlist")
        .allowsHitTesting(false)
    }

    // MARK: - Artwork

    /// The same width-constrained artwork treatment used by on-device playlists.
    @ViewBuilder
    private func artworkHeader(_ details: PlaylistDetails) -> some View {
        let url = details.playlist.thumbnailURL ?? details.videos.first?.thumbnailURL
        PlaylistArtworkHeader(thumbnailURL: url) {
            actionToolbar(details)
        }
    }

    // MARK: - Glass toolbar

    /// Horizontal row of capsule pills with `.ultraThinMaterial` backdrops. Three primary
    /// actions on the left, a `Menu` for secondary actions on the right.
    @ViewBuilder
    private func actionToolbar(_ details: PlaylistDetails) -> some View {
        HStack(spacing: 10) {
            PlaylistHeaderActionButton(title: "Play all", systemImage: "play.fill") {
                guard !details.videos.isEmpty else { return }
                if let first = details.videos.first {
                    player.loadPlaylist(details, startAt: first)
                }
            }
            PlaylistHeaderActionButton(title: "Shuffle", systemImage: "shuffle") {
                guard !details.videos.isEmpty else { return }
                if let first = details.videos.randomElement() {
                    player.loadPlaylist(details, startAt: first, shuffled: true)
                }
            }
            PlaylistHeaderActionButton(title: downloadActionTitle(for: details.playlist.id), systemImage: "arrow.down.circle.fill") {
                let preferred = UserPreferences().preferredQuality
                let downloadQuality: VideoQuality = (preferred.heightCap ?? 1080) > 1080 ? .p1080 : preferred
                playlistDownloads.start(details, quality: downloadQuality)
            }
            .disabled(isPlaylistDownloadActive(details.playlist.id)
                || (details.videos.isEmpty && details.continuationToken == nil))
            Spacer(minLength: 0)
            moreMenu(details)
        }
        .padding(.horizontal)
    }

    /// "More actions" pill — same capsule chrome as the primary actions, just with an ellipsis
    /// icon. Hosts the secondary menu (open in browser / favorite / copy URL).
    @ViewBuilder
    private func moreMenu(_ details: PlaylistDetails) -> some View {
        Menu {
            if let url = details.playlist.youtubeURL {
                ShareLink(item: url) {
                    Label("Share playlist", systemImage: "square.and.arrow.up")
                }
                Button {
                    openURL(url)
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }
            Button {
                Task { await toggleLocalSave(details.playlist) }
            } label: {
                if isSavingLocally {
                    Label("Saving…", systemImage: "arrow.down.circle")
                } else if isSavedLocally {
                    Label("Remove saved playlist", systemImage: "bookmark.fill")
                } else {
                    Label("Save playlist", systemImage: "bookmark")
                }
            }
            .disabled(isSavingLocally)
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

    // MARK: - Videos

    @ViewBuilder
    private func videosList(_ details: PlaylistDetails) -> some View {
        let videos = details.videos
        if videos.isEmpty && !model.isLoadingMore {
            ContentUnavailableView(
                "No Videos",
                systemImage: "rectangle.stack",
                description: Text("This playlist doesn’t contain any available videos.")
            )
            .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoRow(
                        video: video,
                        accessory: .actions(offersPlayNext: true),
                        playbackProgress: showHistoryProgressBars ? playbackProgress[video.id] : nil
                    ) {
                        // Make sure the queue reflects the playlist's order before kicking off
                        // playback, so "next video" actually means the next playlist entry.
                        player.loadPlaylist(details, startAt: video)
                    }
                    .padding(.leading, MediaStyle.listRowInsets.leading)
                    .padding(.trailing, MediaStyle.listRowInsets.trailing)
                    .padding(.vertical, MediaStyle.listRowInsets.top)
                    .onAppear {
                        // Trigger the next-page fetch when the row 5 from the bottom appears.
                        // PlaylistService caches the continuation token on the response struct, so
                        // each `loadMore` advances the cursor for subsequent calls.
                        if index >= videos.count - 5, model.canLoadMore, !model.paginationFailed {
                            Task { await model.loadMore() }
                        }
                    }
                }
                if model.canLoadMore || model.isLoadingMore {
                    MediaPaginationFooter(isLoading: model.isLoadingMore, isRetry: model.paginationFailed) {
                        Task { await model.loadMore() }
                    }
                    .onAppear {
                        if model.canLoadMore, !model.paginationFailed { Task { await model.loadMore() } }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func downloadActionTitle(for playlistID: String) -> String {
        guard let job = playlistDownloads.manifest(for: playlistID) else { return "Download" }
        switch job.status {
        case .queued, .preparing, .downloading: return "Downloading"
        case .paused: return "Resume"
        case .finished: return isFullyDownloaded(job) ? "Downloaded" : "Retry"
        }
    }

    private func isPlaylistDownloadActive(_ playlistID: String) -> Bool {
        guard let job = playlistDownloads.manifest(for: playlistID) else { return false }
        if [.queued, .preparing, .downloading].contains(job.status) { return true }
        return job.status == .finished && isFullyDownloaded(job)
    }

    private func isFullyDownloaded(_ job: PlaylistDownloadManifest) -> Bool {
        let available = Set(downloads.entries.map(\.videoID))
        return job.isPrepared && !job.videos.isEmpty
            && job.videos.allSatisfy { available.contains($0.id) }
    }

    private func toggleLocalSave(_ playlist: Playlist) async {
        if isSavedLocally {
            await localPlaylistService.removeRemotePlaylist(id: playlist.id)
            isSavedLocally = false
        } else {
            isSavingLocally = true
            defer { isSavingLocally = false }
            do {
                try await localPlaylistService.saveRemotePlaylist(playlist)
                isSavedLocally = true
            } catch { return }
        }
    }

}
