import SwiftUI

/// Device-local library following NewPipe's account-free model. Remote channel and playlist
/// destinations remain available when linked from other parts of the app, but this root owns
/// only history, subscriptions, and playlists persisted on this device.
@available(iOS 17.0, *)
struct LibraryScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One strongly typed route set for both local rows and cross-feature requests. Avoiding a
    /// heterogeneous `NavigationPath` lets SwiftUI resolve the first push up front, preserving the
    /// same native transition on a destination's cold and warm openings.
    private enum Destination: Hashable {
        case history
        case subscriptions
        case playlists
        case channel(String)
        case playlist(String)
        case localPlaylist(String)
    }

    let navigationRequest: AppNavigationRequest?
    @State private var localHistoryCount = 0
    @State private var localSubscriptions = LocalSubscriptionStore.shared
    @State private var localPlaylistCount = 0
    @State private var path: [Destination] = []
    @State private var didLoadRootData = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                localHistorySection
            }
            .navigationTitle("Library")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .history: LocalHistoryScreen()
                case .subscriptions:
                    LocalSubscriptionsScreen { path.append(.channel($0)) }
                case .playlists: LocalPlaylistsScreen()
                case .channel(let id): ChannelScreen(channelID: id)
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            // Tie cold-start work to the visible root. A first navigation push cancels this task,
            // preventing late count/account mutations from invalidating the List mid-transition.
            .task(id: path.isEmpty) {
                guard path.isEmpty, !didLoadRootData else { return }
                await loadRootData()
            }
            .refreshable {
                localHistoryCount = await PersistenceWriter.shared.watchHistoryCount()
                localPlaylistCount = await localPlaylistCountFromStore()
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task {
                    let count = await PersistenceWriter.shared.watchHistoryCount()
                    guard path.isEmpty else { return }
                    localHistoryCount = count
                }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let destination = navigationRequest?.destination else { return }
                path.append(route(for: destination))
            }
            .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
                Task {
                    let count = await localPlaylistCountFromStore()
                    guard path.isEmpty else { return }
                    localPlaylistCount = count
                }
            }
        }
    }

    private func loadRootData() async {
        let historyCount = await PersistenceWriter.shared.watchHistoryCount()
        guard !Task.isCancelled, path.isEmpty else { return }
        let playlistCount = await localPlaylistCountFromStore()
        guard !Task.isCancelled, path.isEmpty else { return }
        localHistoryCount = historyCount
        localPlaylistCount = playlistCount

        didLoadRootData = true
    }

    private func localPlaylistCountFromStore() async -> Int {
        let playlists = await LocalPlaylistService().playlists()
        return playlists.count
    }

    private func route(for destination: AppNavigationRequest.Destination) -> Destination {
        switch destination {
        case .channel(let id): .channel(id)
        case .playlist(let id): .playlist(id)
        case .localPlaylist(let id): .localPlaylist(id)
        }
    }

    @ViewBuilder
    private var localHistorySection: some View {
        Section("On this device") {
            LibraryDestinationRow(
                title: "Local history",
                subtitle: countSubtitle(localHistoryCount, noun: "video"),
                systemImage: "clock.arrow.circlepath"
            ) {
                openLocalDestination(.history)
            }

            LibraryDestinationRow(
                title: "Local subscriptions",
                subtitle: countSubtitle(localSubscriptions.subscriptions.count, noun: "channel"),
                systemImage: "person.2.fill"
            ) {
                openLocalDestination(.subscriptions)
            }

            LibraryDestinationRow(
                title: "Local playlists",
                subtitle: countSubtitle(localPlaylistCount, noun: "playlist"),
                systemImage: "music.note.list"
            ) {
                openLocalDestination(.playlists)
            }
        }
    }

    private func openLocalDestination(_ destination: Destination) {
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            path.append(destination)
        }
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

/// Device-only watch history. Unlike `HistoryScreen`, this never calls YouTube and is available
/// without signing in. Rows are backed by `WatchHistoryEntry`, which `PlayerStateManager` updates
/// whenever a video is opened.
@available(iOS 17.0, *)
private struct LocalHistoryScreen: View {
    @Environment(PlayerStateManager.self) private var player
    @State private var entries: [WatchHistorySnapshot] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    private let pageSize = 50

    var body: some View {
        Group {
            if entries.isEmpty && isLoading {
                ProgressView("Loading History…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Local History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you watch will appear here on this device.")
                )
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                VideoRow(
                                    video: video(from: entry),
                                    showsMoreMenu: true,
                                    offersPlayNext: true,
                                    playbackProgress: showHistoryProgressBars ? playbackProgress(for: entry) : nil
                                ) {
                                    player.load(video(from: entry))
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task {
                                            await PersistenceWriter.shared.deleteWatchHistory(videoID: entry.videoID)
                                            entries.removeAll { $0.videoID == entry.videoID }
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if entry.videoID == entries.last?.videoID {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                        } header: {
                            Text(dayTitle(group.day))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Local History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entries.isEmpty && hasMore { await loadMore() }
        }
    }

    private var dayGroups: [(day: Date, entries: [WatchHistorySnapshot])] {
        let calendar = Calendar.autoupdatingCurrent
        return Dictionary(grouping: entries) { calendar.startOfDay(for: $0.watchedAt) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.watchedAt > $1.watchedAt }) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(date: .long, time: .omitted)
    }

    private func video(from entry: WatchHistorySnapshot) -> Video {
        Video(
            id: entry.videoID,
            title: entry.title,
            channelID: "",
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

    /// Match `PlayerStateManager.applyStoredResumePosition` exactly so a row never advertises
    /// progress for a video that playback considers finished or too close to an endpoint.
    private func playbackProgress(for entry: WatchHistorySnapshot) -> Double? {
        entry.resumableProgress
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        let page = await PersistenceWriter.shared.fetchWatchHistory(
            offset: entries.count,
            limit: pageSize
        )
        let existingIDs = Set(entries.map(\.videoID))
        entries.append(contentsOf: page.filter { !existingIDs.contains($0.videoID) })
        hasMore = page.count == pageSize
    }
}
