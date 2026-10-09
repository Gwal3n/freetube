import SwiftUI
import SwiftData
import UIKit

/// Renders search results, suggestions, history, and the empty state. `HomeScreen` owns the search
/// presentation and the history-upsert submit callback.
@available(iOS 17.0, *)
struct SearchContent: View {
    private struct FilterFillRequest: Equatable {
        let resultsRevision: Int
        let filters: SearchVideoFilters
        let isExpanded: Bool
        let blockingRevision: Int
    }

    private struct FilterPageKey: Equatable {
        let request: FilterFillRequest
        let loadedCount: Int
    }

    private enum CustomRange: String, Identifiable {
        case uploaded, length, views
        var id: String { rawValue }
    }

    @Bindable var model: SearchViewModel
    let onRunSearch: (String) -> Void
    let onOpenDestination: (AppNavigationRequest.Destination) -> Void
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arePlaylistsExpanded = false
    @State private var areChannelsExpanded = true
    @State private var areVideosExpanded = true
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("incognitoSkipSearchHistory") private var incognitoSkipSearchHistory = true
    @AppStorage("incognitoHideWatchProgress") private var incognitoHideWatchProgress = true
    @State private var progressByVideoID: [String: Double] = [:]
    @State private var watchStatusByVideoID: [String: WatchHistoryStatus] = [:]
    @State private var videoFilters = SearchVideoFilters()
    @State private var blocklist = VideoBlocklist.shared
    @State private var customRange: CustomRange?
    @State private var lastFilteredPrefetch: FilterPageKey?
    @State private var showingClearSearchHistoryConfirmation = false
    private let navigationLog = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    /// Recently entered search queries, newest first. Tapping one re-runs the search.
    @Query(sort: \SearchHistoryEntry.searchedAt, order: .reverse) private var history: [SearchHistoryEntry]

    var body: some View {
        Group {
            if model.isEditingNewQuery {
                suggestionContent
            } else if let results = model.results {
                resultsList(results)
            } else if model.isLoading {
                MediaListPlaceholder()
            } else if model.didSearchFail {
                ContentUnavailableView {
                    Label("Unable to Search", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        onRunSearch(model.submittedQuery ?? model.query)
                    }
                    .buttonStyle(.bordered)
                }
            } else if !history.isEmpty && !(incognitoEnabled && incognitoSkipSearchHistory) {
                historyList
            } else {
                ContentUnavailableView(
                    "Search YouTube",
                    systemImage: "magnifyingglass",
                    description: Text("Find videos, channels, and playlists.")
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissNativeSearch()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.submittedQuery) { _, _ in
            arePlaylistsExpanded = false
            areChannelsExpanded = true
            areVideosExpanded = true
            videoFilters = SearchVideoFilters()
            lastFilteredPrefetch = nil
        }
        .onChange(of: videoFilters) { _, _ in lastFilteredPrefetch = nil }
        .errorToast($model.errorState)
        .sheet(item: $customRange) { range in
            switch range {
            case .uploaded:
                SearchDateRangeSheet(range: videoFilters.customUploadedRange) { selected in
                    videoFilters.customUploadedRange = selected
                    videoFilters.uploaded = .custom
                }
            case .length:
                SearchNumericRangeSheet(
                    title: "Duration Range", unit: "Minutes",
                    range: videoFilters.customLengthRange
                ) { selected in
                    videoFilters.customLengthRange = selected
                    videoFilters.length = .custom
                }
            case .views:
                SearchNumericRangeSheet(
                    title: "View Count Range", unit: "Views",
                    range: videoFilters.customViewsRange
                ) { selected in
                    videoFilters.customViewsRange = selected
                    videoFilters.views = .custom
                }
            }
        }
    }

    @ViewBuilder
    private func resultsList(_ results: SearchResult) -> some View {
        let now = Date.now
        let visibleChannels = results.channels.filter { !blocklist.blocks($0) }
        let visiblePlaylists = results.playlists.filter { !blocklist.blocks($0) }
        let unblockedVideos = results.videos.filter { !blocklist.blocks($0) }
        let visibleVideos = results.videos.filter {
            !blocklist.blocks($0) && videoFilters.includes($0, status: watchStatusByVideoID[$0.id], now: now)
        }
        if results.videos.isEmpty && results.channels.isEmpty && results.playlists.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No results were found for “\(model.submittedQuery ?? model.query)”.")
            )
        } else if visibleChannels.isEmpty && visiblePlaylists.isEmpty &&
                    unblockedVideos.isEmpty && results.continuationToken == nil {
            ContentUnavailableView(
                "No Unblocked Results",
                systemImage: "hand.raised",
                description: Text("All loaded results match your blocked content rules.")
            )
        } else {
            List {
                if !visibleChannels.isEmpty {
                    Section {
                        if areChannelsExpanded {
                            ForEach(visibleChannels) { channel in
                                Button {
                                    onOpenDestination(.channel(channel.id))
                                } label: {
                                    ChannelRow(channel: channel)
                                }
                                .buttonStyle(ResponsiveButtonStyle())
                                .accessibilityAddTraits(.isLink)
                                .mediaListRow()
                            }
                        }
                    } header: {
                        collapsibleHeader(
                            "Channels",
                            count: visibleChannels.count,
                            isExpanded: $areChannelsExpanded
                        )
                    }
                }
                if !visiblePlaylists.isEmpty {
                    Section {
                        if arePlaylistsExpanded {
                            ForEach(visiblePlaylists) { playlist in
                                PlaylistRow(
                                    playlist: playlist,
                                    onTap: {
                                        navigationLog.info("Search playlist row tapped: \(playlist.id, privacy: .public)")
                                        dismissKeyboard()
                                        onOpenDestination(.playlist(playlist.id))
                                    },
                                    showsMoreMenu: true
                                )
                                .accessibilityAddTraits(.isLink)
                            }
                        }
                    } header: {
                        collapsibleHeader("Playlists", count: visiblePlaylists.count, isExpanded: $arePlaylistsExpanded)
                    }
                }
                if !results.videos.isEmpty {
                    Section {
                        if areVideosExpanded {
                            if visibleVideos.isEmpty {
                                VStack(spacing: 8) {
                                    Group {
                                        if results.continuationToken == nil {
                                            Text("No videos match your filters or blocking rules")
                                        } else {
                                            Text(model.isLoading
                                                 ? "Finding matching videos…"
                                                 : "No loaded videos match. Load more to check the next page.")
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    if videoFilters.isActive {
                                        Button("Reset Filters") {
                                            videoFilters = SearchVideoFilters()
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .listRowSeparator(.hidden)
                            }
                            let lookaheadIDs = Set((videoFilters.isActive || blocklist.rules.isActive ? visibleVideos : unblockedVideos)
                                .suffix(5).map(\.id))
                            ForEach(visibleVideos) { video in
                                VideoRow(
                                    video: video,
                                    accessory: .actions(offersPlayNext: true),
                                    playbackProgress: progressByVideoID[video.id]
                                ) {
                                    // Playback overlays this screen, so preserve the native search
                                    // session and its results for the user's return. Calling
                                    // `dismissSearch()` here can clear the bound query, which in
                                    // turn intentionally resets `SearchViewModel.results`.
                                    dismissKeyboard()
                                    player.load(video)
                                }
                                .onAppear {
                                    guard lookaheadIDs.contains(video.id),
                                          results.continuationToken != nil,
                                          !model.paginationFailed,
                                          !model.isLoading else { return }
                                    if videoFilters.isActive || blocklist.rules.isActive {
                                        // The bounded fill owns sparse first pages. Once there
                                        // are enough visible rows, scrolling near their end can
                                        // prefetch the next page without a repeated button tap.
                                        guard visibleVideos.count >= 12 else { return }
                                        let key = FilterPageKey(
                                            request: .init(
                                                resultsRevision: model.resultsRevision,
                                                filters: videoFilters,
                                                isExpanded: areVideosExpanded,
                                                blockingRevision: blocklist.revision
                                            ),
                                            loadedCount: results.videos.count
                                        )
                                        guard lastFilteredPrefetch != key else { return }
                                        lastFilteredPrefetch = key
                                    }
                                    Task {
                                        await model.loadMore()
                                        if videoFilters.isActive || blocklist.rules.isActive { await fillFilteredResults() }
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            collapsibleHeader("Videos", count: nil, isExpanded: $areVideosExpanded)
                                .frame(maxWidth: .infinity)
                            videoFilterMenu
                        }
                    }
                }
                if areVideosExpanded && (results.continuationToken != nil || model.isLoading) {
                    MediaPaginationFooter(isLoading: model.isLoading, isRetry: model.paginationFailed) {
                        Task {
                            await model.loadMore()
                            if videoFilters.isActive || blocklist.rules.isActive { await fillFilteredResults() }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // The bounded filtered fill owns sparse pages. Ordinary unfiltered
                        // browsing retains its existing automatic footer pagination.
                        guard !videoFilters.isActive, !blocklist.rules.isActive,
                              !model.paginationFailed else { return }
                        Task { await model.loadMore() }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
            .task(id: FilterFillRequest(
                resultsRevision: model.resultsRevision,
                filters: videoFilters,
                isExpanded: areVideosExpanded,
                blockingRevision: blocklist.revision
            )) {
                await fillFilteredResults()
            }
            .task(id: progressLookupID(for: results.videos)) {
                await loadProgress(for: results.videos)
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task { await loadProgress(for: results.videos) }
            }
        }
    }

    private func collapsibleHeader(
        _ title: String,
        count: Int?,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let count {
                    Text(verbatim: count.formatted()).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .frame(minHeight: MediaStyle.actionSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle())
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private var videoFilterMenu: some View {
        Menu {
            Menu {
                ForEach(SearchVideoFilters.Watch.allCases) { option in
                    Button {
                        videoFilters.watch = option
                    } label: {
                        if videoFilters.watch == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Watch history")
            }
            Menu {
                ForEach(SearchVideoFilters.Uploaded.allCases) { option in
                    Button {
                        if option == .custom {
                            customRange = .uploaded
                        } else {
                            videoFilters.uploaded = option
                        }
                    } label: {
                        if videoFilters.uploaded == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Upload date")
            }
            Menu {
                ForEach(SearchVideoFilters.Length.allCases) { option in
                    Button {
                        if option == .custom {
                            customRange = .length
                        } else {
                            videoFilters.length = option
                        }
                    } label: {
                        if videoFilters.length == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Length")
            }
            Menu {
                ForEach(SearchVideoFilters.Views.allCases) { option in
                    Button {
                        if option == .custom {
                            customRange = .views
                        } else {
                            videoFilters.views = option
                        }
                    } label: {
                        if videoFilters.views == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Text("Views")
            }
            Divider()
            Button("Reset Filters") {
                videoFilters = SearchVideoFilters()
            }
            .disabled(!videoFilters.isActive)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.primary)
                        .frame(width: 5, height: 5)
                        .padding(8)
                        .opacity(videoFilters.isActive ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter search videos")
        .accessibilityValue(videoFilters.isActive ? "On" : "Off")
    }

    private func progressLookupID(for videos: [Video]) -> String {
        "\(showHistoryProgressBars):\(incognitoEnabled):\(incognitoHideWatchProgress):" + videos.map(\.id).joined(separator: ",")
    }

    /// Fill a sparse filtered list without turning a very narrow filter into an unlimited stream
    /// of YouTube requests. A later explicit Load more starts another bounded batch.
    private func fillFilteredResults() async {
        let filters = videoFilters
        let blockingRevision = blocklist.revision
        guard (filters.isActive || blocklist.rules.isActive), areVideosExpanded,
              let query = model.submittedQuery else { return }
        let revision = model.resultsRevision
        let targetCount = 12
        let maximumPages = 6

        for _ in 0..<maximumPages {
            while model.isLoading {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            guard !Task.isCancelled,
                  filters == videoFilters,
                  blocklist.revision == blockingRevision,
                  areVideosExpanded,
                  model.resultsRevision == revision,
                  model.submittedQuery == query,
                  !model.isEditingNewQuery,
                  !model.paginationFailed,
                  let results = model.results,
                  let token = results.continuationToken else { return }

            let statuses: [String: WatchHistoryStatus]
            if filters.watch == .all {
                statuses = [:]
            } else {
                let summary = await PersistenceWriter.shared.watchHistorySummary(
                    videoIDs: results.videos.map(\.id)
                )
                guard !Task.isCancelled, filters == videoFilters,
                      blocklist.revision == blockingRevision,
                      model.resultsRevision == revision else { return }
                statuses = summary.statuses
            }
            let now = Date.now
            let visibleCount = results.videos.filter {
                !blocklist.blocks($0) && filters.includes($0, status: statuses[$0.id], now: now)
            }.count
            if visibleCount >= targetCount { return }

            await model.loadMore()
            guard !Task.isCancelled, model.results?.continuationToken != token else { return }
        }
    }

    private func loadProgress(for videos: [Video]) async {
        let ids = videos.map(\.id)
        let summary = await PersistenceWriter.shared.watchHistorySummary(videoIDs: ids)
        guard !Task.isCancelled, model.results?.videos.map(\.id) == ids else { return }
        watchStatusByVideoID = summary.statuses
        progressByVideoID = UserPreferences().displaysWatchProgress ? summary.progress : [:]
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if model.suggestions.isEmpty {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissNativeSearch()
                }
        } else {
            ScrollView {
                SearchSuggestionList(
                    suggestions: model.suggestions,
                    onSelect: { suggestion in
                        model.query = suggestion.text
                        onRunSearch(suggestion.text)
                        dismissKeyboard()
                    },
                    onFill: { suggestion in
                        model.query = suggestion.text
                    }
                )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        List {
            Section {
                ForEach(history) { entry in
                    Button {
                        model.query = entry.query
                        onRunSearch(entry.query)
                        dismissKeyboard()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text(entry.query)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(history[index])
                    }
                    try? modelContext.save()
                }

            } header: {
                HStack {
                    Text("Recent searches")
                    Spacer()
                    Button("Clear") {
                        showingClearSearchHistoryConfirmation = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .textCase(nil)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear recent searches")
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            "Clear recent searches?",
            isPresented: $showingClearSearchHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Searches", role: .destructive) {
                for entry in history { modelContext.delete(entry) }
                try? modelContext.save()
            }
        } message: {
            Text("This removes saved searches from this device.")
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Ends SwiftUI's search presentation as well as resigning the UIKit first responder. Calling
    /// only `resignFirstResponder` leaves `.searchable(isPresented:)` logically active and pins
    /// its expanded drawer after the keyboard has gone away.
    private func dismissNativeSearch() {
        dismissSearch()
        dismissKeyboard()
    }

}

/// Inline field used on Mac, where native `.searchable` collapses to a toolbar button.
@available(iOS 17.0, *)
struct MacInlineSearchField: View {
    @Binding var query: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

@available(iOS 17.0, *)
struct ConditionalSearchable: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let enabled: Bool
    var prompt: String = "Search"

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, isPresented: $isPresented, prompt: Text(prompt))
        } else {
            content
        }
    }
}
