import SwiftUI

/// Device-local library following NewPipe's account-free model. Remote channel and playlist
/// destinations remain available when linked from other parts of the app, but this root owns
/// only history, subscriptions, and playlists persisted on this device.
@available(iOS 17.0, *)
struct LibraryScreen: View {
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("showRecentLibraryVideos") private var showRecentLibraryVideos = true
    @AppStorage("recentLibraryVideoCount") private var recentLibraryVideoCount = 5
    @AppStorage("showResumeLibraryVideos") private var showResumeLibraryVideos = true
    @AppStorage("saveWatchHistory") private var saveWatchHistory = true
    @State private var localHistoryCount: Int?
    @State private var recentVideos: [WatchHistorySnapshot] = []
    @State private var resumableVideos: [WatchHistorySnapshot] = []
    @State private var localSubscriptions = LocalSubscriptionStore.shared
    @State private var localPlaylistCount: Int?
    @State private var externalDestination: AppNavigationRequest.Destination?
    @State private var rootIsVisible = false
    @State private var didLoadRootData = false
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        List {
            localHistorySection
            if saveWatchHistory && showResumeLibraryVideos && !resumableVideos.isEmpty {
                videoShelf("Resume watching", entries: resumableVideos)
            }
            if saveWatchHistory && showRecentLibraryVideos && !recentVideos.isEmpty {
                videoShelf("Recently watched", entries: Array(recentVideos.prefix(recentLibraryVideoCount)))
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    log.info("Library Settings button tapped")
                    NotificationCenter.default.post(name: .freetubeOpenSettings, object: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationDestination(item: $externalDestination) { destination in
            switch destination {
            case .channel(let id):
                ChannelScreen(channelID: id)
                    .onAppear { log.info("Library channel destination appeared") }
            case .playlist(let id):
                PlaylistScreen(playlistID: id)
            case .localPlaylist(let id):
                LocalPlaylistScreen(playlistID: id)
            }
        }
        // Tie cold-start work to the visible root. A first navigation push cancels this task,
        // preventing late count/account mutations from invalidating the List mid-transition.
        .onAppear { rootIsVisible = true }
        .onDisappear { rootIsVisible = false }
        .task(id: rootIsVisible) {
            guard rootIsVisible, !didLoadRootData else { return }
            await loadRootData()
        }
        .refreshable {
            await loadHistorySummary()
            localPlaylistCount = await localPlaylistCountFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            Task {
                await loadHistorySummary()
            }
        }
        .onChange(of: navigationRouter.library?.id, initial: true) { _, _ in
            guard let request = navigationRouter.library else { return }
            navigationRouter.library = nil
            log.info("Library external destination requested")
            externalDestination = request.destination
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task {
                let count = await localPlaylistCountFromStore()
                guard rootIsVisible else { return }
                localPlaylistCount = count
            }
        }
    }

    private func loadRootData() async {
        await loadHistorySummary()
        guard !Task.isCancelled, rootIsVisible else { return }
        let playlistCount = await localPlaylistCountFromStore()
        guard !Task.isCancelled, rootIsVisible else { return }
        localPlaylistCount = playlistCount

        didLoadRootData = true
    }

    private func loadHistorySummary() async {
        let count = await PersistenceWriter.shared.watchHistoryCount()
        let page = await PersistenceWriter.shared.fetchWatchHistory(offset: 0, limit: 100)
        guard !Task.isCancelled, rootIsVisible else { return }
        localHistoryCount = count
        recentVideos = Array(page.prefix(12))
        resumableVideos = Array(page.filter { $0.resumableProgress != nil }.prefix(12))
    }

    private func localPlaylistCountFromStore() async -> Int {
        let playlists = await LocalPlaylistService().playlists()
        return playlists.count
    }

    @ViewBuilder
    private var localHistorySection: some View {
        Section("On this device") {
            NavigationLink {
                LocalHistoryScreen()
                    .onAppear { log.info("Library history destination appeared") }
            } label: {
                LibraryDestinationRow(
                    title: "Local history",
                    subtitle: countSubtitle(localHistoryCount, noun: "video"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .tint(.white)

            NavigationLink {
                LocalSubscriptionsScreen()
                    .onAppear { log.info("Library subscriptions destination appeared") }
            } label: {
                LibraryDestinationRow(
                    title: "Local subscriptions",
                    subtitle: countSubtitle(localSubscriptions.subscriptions.count, noun: "channel"),
                    systemImage: "person.2.fill"
                )
            }
            .tint(.white)

            NavigationLink {
                LocalPlaylistsScreen()
                    .onAppear { log.info("Library playlists destination appeared") }
            } label: {
                LibraryDestinationRow(
                    title: "Local playlists",
                    subtitle: countSubtitle(localPlaylistCount, noun: "playlist"),
                    systemImage: "music.note.list"
                )
            }
            .tint(.white)
        }
    }

    private func videoShelf(_ title: String, entries: [WatchHistorySnapshot]) -> some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(entries) { entry in
                        Button {
                            player.load(video(from: entry))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                VideoThumbnail(
                                    video: video(from: entry),
                                    size: CGSize(width: 160, height: 90),
                                    progress: entry.resumableProgress
                                )
                                Text(entry.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 160, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ResponsiveButtonStyle())
                        .accessibilityLabel("Play \(entry.title)")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 0))
        } header: {
            Text(title)
        }
    }

    private func video(from entry: WatchHistorySnapshot) -> Video {
        Video(
            id: entry.videoID,
            title: entry.title,
            channelID: entry.channelID ?? "",
            channelName: entry.channelName,
            channelThumbnailURL: nil,
            thumbnailURL: entry.thumbnailURL,
            duration: entry.duration > 0 ? entry.duration : nil,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }

    /// Builds the "N videos" / "N playlists" subtitle. When the library response hasn't
    /// returned yet (count is nil), we render "—" rather than a hardcoded "0" so the user can
    /// tell "still loading" from "actually empty".
    private func countSubtitle(_ count: Int?, noun: String) -> String {
        guard let count else { return "—" }
        let plural = count == 1 ? noun : noun + "s"
        return "\(count) \(plural)"
    }
}
