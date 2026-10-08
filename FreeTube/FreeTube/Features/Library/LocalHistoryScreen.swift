import SwiftUI

/// Device-only watch history backed by entries written during local playback.
@available(iOS 17.0, *)
struct LocalHistoryScreen: View {
    enum Mode: Equatable {
        case all
        case continueWatching
    }

    let mode: Mode
    @Environment(PlayerStateManager.self) private var player
    @State private var entries: [WatchHistorySnapshot] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var searchResults: [WatchHistorySnapshot] = []
    @State private var channelNavigation = LocalHistoryChannelNavigationModel()
    @State private var channelToOpen: String?
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    private let pageSize = 50

    init(mode: Mode = .all) {
        self.mode = mode
    }

    var body: some View {
        Group {
            if !hasLoaded {
                MediaListPlaceholder()
            } else if !searchText.isEmpty && visibleEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if visibleEntries.isEmpty && !hasMore {
                if mode == .continueWatching {
                    ContentUnavailableView(
                        "Nothing to Resume",
                        systemImage: "play.circle",
                        description: Text("Partially watched videos will appear here.")
                    )
                } else {
                    ContentUnavailableView(
                        "No Local History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Videos you watch will appear here on this device.")
                    )
                }
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                let video = video(from: entry)
                                VideoRow(
                                    video: video,
                                    accessory: .actions(offersPlayNext: true),
                                    playbackProgress: showHistoryProgressBars ? entry.resumableProgress : nil,
                                    onOpenChannel: {
                                        if let channelID = entry.channelID, !channelID.isEmpty {
                                            channelToOpen = channelID
                                        } else {
                                            Task {
                                                channelToOpen = await channelNavigation.channelID(for: entry.videoID)
                                            }
                                        }
                                    }
                                ) {
                                    player.load(video)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await remove(entry) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .onAppear {
                                    if searchText.isEmpty && entry.videoID == visibleEntries.last?.videoID {
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
        .navigationTitle(mode == .continueWatching
                         ? String(localized: "Continue Watching")
                         : String(localized: "Local History"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: mode == .continueWatching
                    ? Text("Search continue watching") : Text("Search history"))
        .toolbar {
            if channelNavigation.isResolving {
                ProgressView()
                    .accessibilityLabel("Opening channel")
            }
        }
        .navigationDestination(item: $channelToOpen) { channelID in
            ChannelScreen(channelID: channelID)
        }
        .errorToast(Bindable(channelNavigation).errorState)
        .task {
            if entries.isEmpty && hasMore { await loadMore() }
        }
        .task(id: searchText) {
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await PersistenceWriter.shared.searchWatchHistory(searchText)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }

    private var visibleEntries: [WatchHistorySnapshot] {
        let source = searchText.isEmpty ? entries : searchResults
        return mode == .continueWatching
            ? source.filter { $0.resumableProgress != nil }
            : source
    }

    private var dayGroups: [(day: Date, entries: [WatchHistorySnapshot])] {
        let calendar = Calendar.autoupdatingCurrent
        return Dictionary(grouping: visibleEntries) { calendar.startOfDay(for: $0.watchedAt) }
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

    private func remove(_ entry: WatchHistorySnapshot) async {
        await PersistenceWriter.shared.deleteWatchHistory(videoID: entry.videoID)
        entries.removeAll { $0.videoID == entry.videoID }
        searchResults.removeAll { $0.videoID == entry.videoID }
        if mode == .continueWatching && searchText.isEmpty && visibleEntries.isEmpty && hasMore {
            await loadMore()
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        var newlyResumable = 0
        repeat {
            let page = await PersistenceWriter.shared.fetchWatchHistory(
                offset: entries.count,
                limit: pageSize
            )
            guard !Task.isCancelled else { return }
            let existingIDs = Set(entries.map(\.videoID))
            let newEntries = page.filter { !existingIDs.contains($0.videoID) }
            entries.append(contentsOf: newEntries)
            newlyResumable += newEntries.filter { $0.resumableProgress != nil }.count
            hasMore = page.count == pageSize && !newEntries.isEmpty
        } while mode == .continueWatching && hasMore && newlyResumable < 20
        hasLoaded = true
    }
}
