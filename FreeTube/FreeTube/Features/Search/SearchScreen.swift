import SwiftUI
import SwiftData
import UIKit

/// Renders search results, suggestions, history, and the empty state. `HomeScreen` owns the search
/// presentation and the history-upsert submit callback.
@available(iOS 17.0, *)
struct SearchContent: View {
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
    @State private var progressByVideoID: [String: Double] = [:]
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
            } else if !history.isEmpty {
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
        }
        .errorToast($model.errorState)
    }

    @ViewBuilder
    private func resultsList(_ results: SearchResult) -> some View {
        if results.videos.isEmpty && results.channels.isEmpty && results.playlists.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No results were found for “\(model.submittedQuery ?? model.query)”.")
            )
        } else {
            List {
                if !results.channels.isEmpty {
                    Section {
                        if areChannelsExpanded {
                            ForEach(results.channels) { channel in
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
                            count: results.channels.count,
                            isExpanded: $areChannelsExpanded
                        )
                    }
                }
                if !results.playlists.isEmpty {
                    Section {
                        if arePlaylistsExpanded {
                            ForEach(results.playlists) { playlist in
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
                        collapsibleHeader("Playlists", count: results.playlists.count, isExpanded: $arePlaylistsExpanded)
                    }
                }
                if !results.videos.isEmpty {
                    Section {
                        if areVideosExpanded {
                            let lookaheadIDs = Set(results.videos.suffix(5).map(\.id))
                            ForEach(results.videos) { video in
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
                                    Task { await model.loadMore() }
                                }
                            }
                        }
                    } header: {
                        collapsibleHeader("Videos", count: nil, isExpanded: $areVideosExpanded)
                    }
                }
                if results.continuationToken != nil || model.isLoading {
                    MediaPaginationFooter(isLoading: model.isLoading, isRetry: model.paginationFailed) {
                        Task { await model.loadMore() }
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        guard !model.paginationFailed else { return }
                        Task { await model.loadMore() }
                    }
                }
                if player.miniPlayerVisible && !player.fullScreenPresented {
                    Color.clear
                        .frame(height: 96)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
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

    private func progressLookupID(for videos: [Video]) -> String {
        "\(showHistoryProgressBars):" + videos.map(\.id).joined(separator: ",")
    }

    private func loadProgress(for videos: [Video]) async {
        guard showHistoryProgressBars else {
            progressByVideoID = [:]
            return
        }
        progressByVideoID = await PersistenceWriter.shared.watchProgress(
            videoIDs: videos.map(\.id)
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
            Section("Recent searches") {
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

                if !history.isEmpty {
                    Button("Clear all", role: .destructive) {
                        for entry in history { modelContext.delete(entry) }
                        try? modelContext.save()
                    }
                }
            }
            if player.miniPlayerVisible && !player.fullScreenPresented {
                Color.clear
                    .frame(height: 96)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
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
