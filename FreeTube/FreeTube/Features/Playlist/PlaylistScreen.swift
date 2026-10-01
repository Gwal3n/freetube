import SwiftUI
import Kingfisher

/// Playlist detail screen. Top-down layout:
///   1. Large playlist artwork
///   2. Title + channel + video-count metadata
///   3. Glass-pill action toolbar — Play all / Shuffle all / Download all + More menu
///   4. List of videos
///
/// Public YouTube playlists are read-only. Editing and reordering live exclusively in the local
/// playlist screens, keeping this view independent from account-only mutation endpoints.
@available(iOS 17.0, *)
struct PlaylistScreen: View {
    @State private var model: PlaylistViewModel
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.openURL) private var openURL
    @State private var isSavedLocally = false
    @State private var isSavingLocally = false
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
                    // The artwork owns the top edge and actions; metadata keeps the standard
                    // content inset below it. The image continues beneath the transparent bar.
                    VStack(alignment: .leading, spacing: 16) {
                        artworkHeader(details)
                        PlaylistMetadataBlock(details: details, isExpanded: $isDetailsExpanded)
                    }
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        blurredArtworkBackground(for: details)
                    }

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

    // MARK: - Blurred artwork backdrop

    /// Reserves the same broad geometry as the loaded artwork, metadata, and first rows. Keeping
    /// this static avoids shimmer work and prevents the whole page from jumping after resolution.
    private var playlistPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(MediaStyle.placeholderFill)
                .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 20)
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 150, height: 11)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: MediaStyle.spacing) {
                        RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                            .fill(.quaternary)
                            .frame(width: 144, height: 81)
                        VStack(alignment: .leading, spacing: 9) {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 12)
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 90, height: 9)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading playlist")
        .allowsHitTesting(false)
    }

    /// Heavily-blurred, dimmed copy of the playlist artwork behind the header. It extends
    /// under the status/navigation bar and ends with the header's toolbar.
    ///
    /// Three layers stacked inside:
    ///   1. The artwork itself, `.resizable().scaledToFill().blur(radius: 60)`.
    ///   2. A dark overlay (`Color.black.opacity(0.55)`) for foreground-text contrast.
    ///   3. A subtle bottom-edge gradient that fades into the screen background so the divider
    ///      below doesn't look pasted on.
    @ViewBuilder
    private func blurredArtworkBackground(for details: PlaylistDetails) -> some View {
        let url = details.playlist.thumbnailURL ?? details.videos.first?.thumbnailURL
        ZStack {
            // Heavy blur — we can downsample aggressively (200×112) since the source pixels
            // are mostly thrown away by the 60-radius blur anyway.
            KFImage(url)
                .thumbnail(size: CGSize(width: 200, height: 112)) {
                    Color.black
                }
                .resizable()
                .scaledToFill()
                .blur(radius: 60)
            Color.black.opacity(0.55)
            LinearGradient(
                colors: [Color.clear, Color.clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Artwork

    /// Width-constrained full-bleed playlist artwork. GeometryReader keeps the image's frame
    /// within the actual viewport instead of letting a scaled image widen the scroll content.
    @ViewBuilder
    private func artworkHeader(_ details: PlaylistDetails) -> some View {
        let url = details.playlist.thumbnailURL ?? details.videos.first?.thumbnailURL
        GeometryReader { geometry in
            KFImage(url)
                .thumbnail(size: CGSize(width: 500, height: 281)) {
                    MediaStyle.placeholderFill
                }
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .overlay(alignment: .bottom) {
                    actionToolbar(details)
                        .padding(.bottom, 12)
                }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    // MARK: - Glass toolbar

    /// Horizontal row of capsule pills with `.ultraThinMaterial` backdrops. Three primary
    /// actions on the left, a `Menu` for secondary actions on the right.
    @ViewBuilder
    private func actionToolbar(_ details: PlaylistDetails) -> some View {
        HStack(spacing: 10) {
            glassPill(title: "Play all", systemImage: "play.fill") {
                guard !details.videos.isEmpty else { return }
                if let first = details.videos.first {
                    player.loadPlaylist(details, startAt: first)
                }
            }
            glassPill(title: "Shuffle", systemImage: "shuffle") {
                guard !details.videos.isEmpty else { return }
                if let first = details.videos.randomElement() {
                    player.loadPlaylist(details, startAt: first, shuffled: true)
                }
            }
            glassPill(title: "Download", systemImage: "arrow.down.circle.fill") {
                enqueueAllDownloads(details.videos)
            }
            Spacer(minLength: 0)
            moreMenu(details)
        }
        .padding(.horizontal)
    }

    /// Capsule action button styled to match the "glass" look used on the full-screen player —
    /// `.ultraThinMaterial` backdrop, hairline white stroke, white icon + label.
    private func glassPill(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .frame(minHeight: MediaStyle.actionSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle())
    }

    /// "More actions" pill — same capsule chrome as the primary actions, just with an ellipsis
    /// icon. Hosts the secondary menu (open in browser / favorite / copy URL).
    @ViewBuilder
    private func moreMenu(_ details: PlaylistDetails) -> some View {
        Menu {
            if let url = playlistURL(details.playlist.id) {
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

    /// Fires off `ensureDownloaded` for every playlist video **in parallel**, fire-and-forget,
    /// so each one gets added to the Downloads queue (DownloadManager.tasks) immediately and the
    /// user sees the whole playlist appear in the Downloads tab. The actual yt-dlp work still
    /// runs serially behind `PythonRunner`'s FIFO, but the queue list reflects everything that
    /// needs to happen, which is what the user wants to see.
    ///
    /// Sequential `await`-in-a-loop (the previous implementation) only enqueued the next item
    /// after the previous finished, so the UI made it look like the Download All button was
    /// downloading one track and ignoring the rest.
    private func enqueueAllDownloads(_ videos: [Video]) {
        let quality = UserPreferences().preferredQuality
        for video in videos {
            Task {
                _ = try? await DownloadManager.shared.ensureDownloaded(video: video, quality: quality)
            }
        }
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

    /// YouTube's playlist URLs use the bare playlist id, stripping the `VL` prefix YouTubeKit
    /// adds for browse requests.
    private func playlistURL(_ id: String) -> URL? {
        let bare = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        return URL(string: "https://www.youtube.com/playlist?list=\(bare)")
    }
}
