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
        let blockingRevision: Int
    }

    @Bindable var model: SearchViewModel
    let onRunSearch: (String) -> Void
    let onOpenDestination: (AppNavigationRequest.Destination) -> Void
    /// Opens the native field with this query filled in, ready to submit.
    let onEditQuery: (String) -> Void
    let onCustomUploaded: () -> Void
    let onCustomLength: () -> Void
    let onCustomViews: () -> Void
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("incognitoSkipSearchHistory") private var incognitoSkipSearchHistory = true
    @AppStorage("incognitoHideWatchProgress") private var incognitoHideWatchProgress = true
    @AppStorage("recentChannelsJSON") private var recentChannelsJSON = "[]"
    @AppStorage("autoLoadMoreSearchItems") private var autoLoadMoreSearchItems = true
    /// Shared with Feed so Search and subscription browsing keep the same density and avatar
    /// chrome. The browsing settings toggles write these same keys.
    @AppStorage("largeSubscriptionFeedThumbnails") private var largeVideoThumbnails = false
    @AppStorage("showFeedChannelAvatars") private var showChannelAvatars = true
    @State private var blocklist = VideoBlocklist.shared
    @State private var showingClearSearchHistoryConfirmation = false
    @State private var visibleRecentChannelCount = Self.recentChannelPageSize
    @AppStorage(RecentHistoryLimits.searchKey) private var recentSearchLimit = RecentHistoryLimits.defaultSearchLimit
    /// Recent channels start with this many rows; More reveals the same number again.
    private static let recentChannelPageSize = 3
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
            } else if (!history.isEmpty || !recentChannels.isEmpty)
                        && !(incognitoEnabled && incognitoSkipSearchHistory) {
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
            model.invalidateFilteredPrefetch()
        }
        .onChange(of: model.videoFilters) { oldValue, _ in
            model.invalidateFilteredPrefetch()
            model.serverFiltersDidChange(from: oldValue)
        }
        .errorToast($model.errorState)
    }

    @ViewBuilder
    private func resultsList(_ results: SearchResult) -> some View {
        let now = Date.now
        let unblockedItems = results.items.filter { !isBlocked($0) }
        let visibleItems = unblockedItems.filter {
            model.includes($0, now: now, status: model.watchStatus(for: $0))
        }
        if results.items.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No results were found for “\(model.submittedQuery ?? model.query)”.")
            } actions: {
                if model.videoFilters.isActive {
                    Button("Reset Filters") {
                        model.videoFilters = model.videoFilters.resettingFilters()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if unblockedItems.isEmpty && results.continuationToken == nil {
            ContentUnavailableView(
                "No Unblocked Results",
                systemImage: "hand.raised",
                description: Text("All loaded results match your blocked content rules.")
            )
        } else {
            List {
                resultsHeader

                if visibleItems.isEmpty {
                    VStack(spacing: 8) {
                        Group {
                            if results.continuationToken == nil {
                                Text("No results match your filters or blocking rules")
                            } else {
                                Text(model.isLoading
                                     ? "Finding matching results…"
                                     : "No loaded results match. Load more to check the next page.")
                            }
                        }
                        .foregroundStyle(.secondary)
                        if model.videoFilters.isActive {
                            Button("Reset Filters") {
                                model.videoFilters = model.videoFilters.resettingFilters()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .listRowSeparator(.hidden)
                }

                let lookaheadIDs = Set(
                    (model.videoFilters.isActive || blocklist.rules.isActive ? visibleItems : unblockedItems)
                        .suffix(5)
                        .map(\.id)
                )
                ForEach(visibleItems) { hit in
                    searchHitRow(hit)
                        .onAppear {
                            guard autoLoadMoreSearchItems, lookaheadIDs.contains(hit.id),
                                  results.continuationToken != nil,
                                  !model.paginationFailed,
                                  !model.isLoading else { return }
                            if model.videoFilters.isActive || blocklist.rules.isActive {
                                guard visibleItems.count >= 12 else { return }
                                guard model.shouldPrefetchFilteredPage(
                                    loadedCount: results.items.count,
                                    blockingRevision: blocklist.revision
                                ) else { return }
                            }
                            Task {
                                await model.loadMore()
                                if model.videoFilters.isActive || blocklist.rules.isActive {
                                    await fillFilteredResults()
                                }
                            }
                        }
                }

                if results.continuationToken != nil || model.isLoading {
                    MediaPaginationFooter(isLoading: model.isLoading, isRetry: model.paginationFailed) {
                        Task {
                            await model.loadMore()
                            if model.videoFilters.isActive || blocklist.rules.isActive {
                                await fillFilteredResults()
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        guard autoLoadMoreSearchItems, !model.videoFilters.isActive,
                              !blocklist.rules.isActive, !model.paginationFailed else { return }
                        Task { await model.loadMore() }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.refresh() }
            .task(id: FilterFillRequest(
                resultsRevision: model.resultsRevision,
                filters: model.videoFilters,
                blockingRevision: blocklist.revision
            )) {
                await fillFilteredResults()
            }
            .task(id: progressLookupID(for: results.videos)) {
                await model.loadWatchProgress(for: results.videos)
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task { await model.loadWatchProgress(for: results.videos) }
            }
        }
    }

    @ViewBuilder
    private func searchHitRow(_ hit: SearchHit) -> some View {
        switch hit {
        case .video(let video):
            searchVideoRow(video)
        case .channel(let channel):
            Button {
                dismissKeyboard()
                onOpenDestination(.channel(channel.id))
            } label: {
                ChannelRow(channel: channel)
                    .frame(minHeight: mixedResultRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .mediaListRow()
            .accessibilityAddTraits(.isLink)
        case .playlist(let playlist):
            PlaylistRow(
                playlist: playlist,
                onTap: {
                    navigationLog.info("Search playlist row tapped: \(playlist.id, privacy: .public)")
                    dismissKeyboard()
                    onOpenDestination(.playlist(playlist.id))
                },
                showsMoreMenu: true
            )
            .frame(minHeight: mixedResultRowHeight)
            .accessibilityAddTraits(.isLink)
        }
    }

    /// Channel and playlist rows take the compact video thumbnail's height, centered, so mixed
    /// results share one rhythm. Large thumbnail cards are far taller and keep their own rows.
    private var mixedResultRowHeight: CGFloat? {
        largeVideoThumbnails ? nil : MediaStyle.compactVideoThumbnailSize(for: dynamicTypeSize).height
    }

    /// Same density and avatar treatment as the subscription feed, so Search does not look like a
    /// second, poorer list style. Channel taps route through `onOpenDestination` (which ends the
    /// searchable session first) instead of a List `NavigationLink`, which is what drew the
    /// trailing disclosure chevron on every video row.
    @ViewBuilder
    private func searchVideoRow(_ video: Video) -> some View {
        let openChannel: (() -> Void)? = video.channelID.isEmpty
            ? nil
            : {
                dismissKeyboard()
                onOpenDestination(.channel(video.channelID))
            }
        if largeVideoThumbnails {
            VideoCard(
                video: video,
                onTap: {
                    // Playback overlays this screen, so preserve the native search session and its
                    // results for the user's return. Calling `dismissSearch()` here can clear the
                    // bound query, which in turn intentionally resets `SearchViewModel.results`.
                    dismissKeyboard()
                    player.load(video)
                },
                showsMoreMenu: true,
                offersPlayNext: true,
                showsChannelAvatar: showChannelAvatars,
                onTapChannel: openChannel,
                playbackProgress: model.progressByVideoID[video.id],
                watchStatus: displaysWatchProgress ? model.watchStatusByVideoID[video.id] : nil
            )
        } else {
            VideoRow(
                video: video,
                accessory: .actions(offersPlayNext: true),
                showsChannelAvatar: showChannelAvatars,
                playbackProgress: model.progressByVideoID[video.id],
                watchStatus: displaysWatchProgress ? model.watchStatusByVideoID[video.id] : nil,
                onOpenChannel: openChannel,
                onTapChannel: openChannel
            ) {
                dismissKeyboard()
                player.load(video)
            }
        }
    }

    private func isBlocked(_ hit: SearchHit) -> Bool {
        switch hit {
        case .video(let video): blocklist.blocks(video)
        case .channel(let channel): blocklist.blocks(channel)
        case .playlist(let playlist): blocklist.blocks(playlist)
        }
    }

    private func progressLookupID(for videos: [Video]) -> String {
        "\(showHistoryProgressBars):\(incognitoEnabled):\(incognitoHideWatchProgress):" + videos.map(\.id).joined(separator: ",")
    }

    private func fillFilteredResults() async {
        await model.fillFilteredResults(
            autoLoadMore: autoLoadMoreSearchItems,
            blockingActive: blocklist.rules.isActive,
            isBlocked: isBlocked
        )
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
                    typedText: model.query,
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
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        // Headings are ordinary rows rather than Section headers, which a plain List pins.
        List {
            let channels = recentChannels
            if !channels.isEmpty {
                historyHeading("Recent channels", clearLabel: "Clear recent channels") {
                    recentChannelsJSON = "[]"
                    visibleRecentChannelCount = Self.recentChannelPageSize
                }
                ForEach(Array(channels.prefix(visibleRecentChannelCount))) { entry in
                    NavigationLink {
                        ChannelScreen(channelID: entry.id)
                    } label: {
                        ChannelRow(channel: entry.channel)
                    }
                    .mediaListRow()
                }
                .onDelete { offsets in
                    var entries = channels
                    entries.remove(atOffsets: offsets)
                    if let json = RecentChannel.json(from: entries) {
                        recentChannelsJSON = json
                    }
                }
                if channels.count > visibleRecentChannelCount {
                    Button {
                        visibleRecentChannelCount += Self.recentChannelPageSize
                    } label: {
                        Text("More")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Show more recent channels")
                }
            }
            let searches = Array(history.prefix(recentSearchLimit))
            if !searches.isEmpty {
                historyHeading("Recent searches", clearLabel: "Clear recent searches") {
                    showingClearSearchHistoryConfirmation = true
                }
                ForEach(searches) { entry in
                    Button {
                        if isSearching || MacIntegration.isRunningOnMac {
                            model.query = entry.query
                            onRunSearch(entry.query)
                            dismissKeyboard()
                        } else {
                            // Running from the inactive screen would show results outside the
                            // active search; fill the field instead and submit from there.
                            onEditQuery(entry.query)
                        }
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
                        modelContext.delete(searches[index])
                    }
                    try? modelContext.save()
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
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

    /// Active search hides the navigation title and toolbar, so the results begin with their own
    /// title, result-type picker, and filter menu. It is the first List row and scrolls away with
    /// the results; a bar pinned over the List fought its scroll edge.
    private var resultsHeader: some View {
        // Mirrors Feed's native layout: space for its 44 pt toolbar row, the 34 pt bold large
        // title, then a subtitle row with the picker leading and the filter where Feed shows its
        // refresh age.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 44)
            Text("Search")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 4)
                .padding(.top, 16.67)
            HStack(spacing: 8) {
                resultTypePicker
                SearchVideoFilterMenu(
                    filters: $model.videoFilters,
                    onCustomUploaded: onCustomUploaded,
                    onCustomLength: onCustomLength,
                    onCustomViews: onCustomViews
                )
                .fixedSize()
            }
            .padding(.top, 26.33)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// A quiet subtitle beneath the Search title, styled like Feed's group picker. The label sits
    /// in a full-width leading frame, so a longer choice never resizes the header row.
    private var resultTypePicker: some View {
        Menu {
            ForEach(SearchVideoFilters.ResultType.allCases) { option in
                Button {
                    model.videoFilters.resultType = option
                } label: {
                    if model.videoFilters.resultType == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.videoFilters.resultType.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .accessibilityLabel("Result type")
        .accessibilityValue(model.videoFilters.resultType.title)
    }

    /// A scrolling section heading with a trailing Clear action.
    private func historyHeading(
        _ title: LocalizedStringKey,
        clearLabel: LocalizedStringKey,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Clear", action: onClear)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(clearLabel)
        }
        .padding(.top, 8)
        .listRowSeparator(.hidden)
        .deleteDisabled(true)
    }

    private var recentChannels: [RecentChannel] {
        RecentChannel.entries(from: recentChannelsJSON)
    }

    private var displaysWatchProgress: Bool {
        showHistoryProgressBars && !(incognitoEnabled && incognitoHideWatchProgress)
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
            // Always visible below the title, so the inactive screen never hides the field on scroll.
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(prompt)
            )
        } else {
            content
        }
    }
}
