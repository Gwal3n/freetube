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
    @State private var blocklist = VideoBlocklist.shared
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var historyRevision = 0
    @State private var hasLoaded = false
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var searchResults: [WatchHistorySnapshot] = []
    @State private var channelNavigation = LocalHistoryChannelNavigationModel()
    @State private var historyPlayback = HistoryPlaybackViewModel.shared
    @State private var channelToOpen: String?
    @State private var showSavedMoments = false
    @State private var momentToOpen: SavedMoment?
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("incognitoHideWatchProgress") private var incognitoHideWatchProgress = true
    private let pageSize = 50

    init(mode: Mode = .all) {
        self.mode = mode
    }

    var body: some View {
        Group {
            if !hasLoaded {
                MediaListPlaceholder()
            } else if !searchText.isEmpty && visibleEntries.isEmpty {
                ScrollView {
                    ContentUnavailableView.search(text: searchText)
                        .containerRelativeFrame(.vertical)
                }
                .refreshable { await refreshHistory() }
            } else if visibleEntries.isEmpty && !hasMore {
                ScrollView {
                    Group {
                        if !entries.isEmpty && entries.allSatisfy({
                            blocklist.blocks(title: $0.title, channelID: $0.channelID, channelName: $0.channelName)
                        }) {
                            ContentUnavailableView(
                                "History Hidden",
                                systemImage: "hand.raised",
                                description: Text("Change blocked content in Settings to see these videos again.")
                            )
                        } else if mode == .continueWatching {
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
                    }
                    .containerRelativeFrame(.vertical)
                }
                .refreshable { await refreshHistory() }
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                let video = video(from: entry)
                                VideoRow(
                                    video: video,
                                    accessory: .actions(offersPlayNext: true),
                                    playbackProgress: showHistoryProgressBars && !(incognitoEnabled && incognitoHideWatchProgress)
                                        ? entry.resumableProgress : nil,
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
                                    historyPlayback.open(entry, video: video, player: player)
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
                    if visibleEntries.isEmpty && hasMore {
                        Button("Load more history") {
                            Task { await loadMore() }
                        }
                        .disabled(isLoading || isRefreshing)
                    }
                }
                .listStyle(.plain)
                .refreshable { await refreshHistory() }
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
            if mode == .all {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSavedMoments = true
                    } label: {
                        Label("Saved moments", systemImage: "bookmark")
                    }
                    .tint(.white)
                }
            }
        }
        .sheet(isPresented: $showSavedMoments, onDismiss: {
            guard let moment = momentToOpen else { return }
            momentToOpen = nil
            player.load(moment.video, startAt: moment.time)
        }) {
            SavedMomentsScreen { moment in
                momentToOpen = moment
                showSavedMoments = false
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
        let source = (searchText.isEmpty ? entries : searchResults).filter {
            !blocklist.blocks(title: $0.title, channelID: $0.channelID, channelName: $0.channelName)
        }
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

    /// Re-read the first page without blanking the list. An older pagination request may still
    /// complete after the refresh starts, so its revision must no longer be allowed to append.
    private func refreshHistory() async {
        historyRevision &+= 1
        let revision = historyRevision
        isRefreshing = true
        isLoading = false
        defer {
            if historyRevision == revision { isRefreshing = false }
        }

        let page = await PersistenceWriter.shared.fetchWatchHistory(offset: 0, limit: pageSize)
        guard !Task.isCancelled, historyRevision == revision else { return }
        entries = page
        hasMore = page.count == pageSize
        hasLoaded = true

        let query = searchText
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let results = await PersistenceWriter.shared.searchWatchHistory(query)
            guard !Task.isCancelled, historyRevision == revision else { return }
            if searchText == query { searchResults = results }
        }

        isRefreshing = false
        if mode == .continueWatching && hasMore &&
            entries.filter({ $0.resumableProgress != nil }).count < 20 {
            await loadMore()
        }
    }

    private func loadMore() async {
        guard !isLoading, !isRefreshing, hasMore else { return }
        let revision = historyRevision
        isLoading = true
        defer {
            if historyRevision == revision { isLoading = false }
        }
        var newlyResumable = 0
        repeat {
            let page = await PersistenceWriter.shared.fetchWatchHistory(
                offset: entries.count,
                limit: pageSize
            )
            guard !Task.isCancelled, historyRevision == revision else { return }
            let existingIDs = Set(entries.map(\.videoID))
            let newEntries = page.filter { !existingIDs.contains($0.videoID) }
            entries.append(contentsOf: newEntries)
            newlyResumable += newEntries.filter { $0.resumableProgress != nil }.count
            hasMore = page.count == pageSize && !newEntries.isEmpty
        } while mode == .continueWatching && hasMore && newlyResumable < 20
        hasLoaded = true
    }
}
