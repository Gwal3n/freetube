import SwiftUI

/// Pushed when the user taps one of the rows in `ChannelScreen`'s tab menu. Reads its content
/// reactively from the parent `ChannelViewModel` (instead of receiving a frozen array) so that
/// when pagination appends new items, the list updates without a re-push.
///
/// **Pagination:** when one of the last few rows appears on screen and the VM reports
/// `canLoadMore(for:)`, we kick off `loadMore(for:)`. The VM dedupes concurrent calls so rapid
/// scrolling doesn't spam YouTube with continuation requests.
@available(iOS 17.0, *)
struct ChannelTabScreen: View {
    let title: String
    let kind: ChannelViewModel.Tab
    let model: ChannelViewModel

    @Environment(PlayerStateManager.self) private var player
    @State private var videoSort: ChannelVideoSort = .newest

    /// How many rows from the bottom we trigger pagination. 5 keeps the next page warm before the
    /// user's thumb arrives at the actual last row.
    private let prefetchLookahead = 5

    var body: some View {
        Group {
            if kind == .playlists {
                playlistList(playlists)
            } else {
                videoList(videos)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == .allVideos {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort videos", selection: $videoSort) {
                            ForEach(ChannelVideoSort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    } label: {
                        Label(videoSort.title, systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .task(id: videoSort) {
            guard kind == .allVideos else { return }
            await model.loadVideos(sort: videoSort)
        }
    }

    // MARK: - Data accessors

    private var videos: [Video] {
        guard let details = model.details else { return [] }
        switch kind {
        case .allVideos:
            return model.videos(for: videoSort)
        case .shorts:
            return details.shorts.items
        case .directs:
            return details.directs.items
        case .playlists:
            return []
        }
    }

    private var playlists: [Playlist] {
        model.details?.playlists.items ?? []
    }

    // MARK: - Lists

    @ViewBuilder
    private func videoList(_ videos: [Video]) -> some View {
        if kind == .allVideos, videos.isEmpty,
           (!model.hasLoadedVideos(for: videoSort) || model.isLoadingVideos(for: videoSort)) {
            LoadingView()
        } else if videos.isEmpty {
            EmptyStateView(systemImage: "tray", title: "Nothing here", message: "This channel hasn't posted any \(title.lowercased()) yet.")
        } else {
            List {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoRow(video: video) { player.load(video) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear { prefetchIfNeeded(currentIndex: index, total: videos.count) }
                }
                if canLoadMoreCurrentContent {
                    loadMoreFooter
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func playlistList(_ playlists: [Playlist]) -> some View {
        if playlists.isEmpty {
            EmptyStateView(systemImage: "rectangle.stack", title: "No playlists", message: "This channel has no public playlists.")
        } else {
            List {
                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistScreen(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .buttonStyle(.plain)
                    .onAppear { prefetchIfNeeded(currentIndex: index, total: playlists.count) }
                }
                if model.canLoadMore(for: kind) {
                    loadMoreFooter
                }
            }
            .listStyle(.plain)
        }
    }

    /// Centered spinner pinned at the bottom of the list while a continuation request is in
    /// flight. Also acts as a tap target — appearing on screen kicks off `loadMore` for cases
    /// where the user scrolled past the lookahead trigger before the previous page completed.
    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .onAppear {
            Task { await loadMoreCurrentContent() }
        }
    }

    // MARK: - Pagination trigger

    private func prefetchIfNeeded(currentIndex: Int, total: Int) {
        guard currentIndex >= total - prefetchLookahead else { return }
        if kind == .allVideos {
            guard model.canLoadMoreVideos(sort: videoSort) else { return }
            Task { await model.loadMoreVideos(sort: videoSort) }
            return
        }
        guard model.canLoadMore(for: kind) else { return }
        Task { await model.loadMore(for: kind) }
    }

    private var canLoadMoreCurrentContent: Bool {
        kind == .allVideos
            ? model.canLoadMoreVideos(sort: videoSort)
            : model.canLoadMore(for: kind)
    }

    private func loadMoreCurrentContent() async {
        if kind == .allVideos {
            await model.loadMoreVideos(sort: videoSort)
        } else {
            await model.loadMore(for: kind)
        }
    }
}
