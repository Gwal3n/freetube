import SwiftUI
import SwiftData
import UIKit

/// Renders search results, suggestions, history, and the empty state. `HomeScreen` owns the search
/// presentation and the history-upsert submit callback.
@available(iOS 17.0, *)
struct SearchContent: View {
    @Bindable var model: SearchViewModel
    let onRunSearch: (String) -> Void
    let onDismissSearchPresentation: () -> Void
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var arePlaylistsExpanded = false
    @State private var areChannelsExpanded = true
    @State private var areVideosExpanded = true
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @State private var progressByVideoID: [String: Double] = [:]

    /// Recently entered search queries, newest first. Tapping one re-runs the search.
    @Query(sort: \SearchHistoryEntry.searchedAt, order: .reverse) private var history: [SearchHistoryEntry]

    var body: some View {
        Group {
            if model.isEditingNewQuery {
                suggestionContent
            } else if let results = model.results {
                resultsList(results)
            } else if model.isLoading {
                LoadingView()
            } else if !history.isEmpty {
                historyList
            } else {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Search YouTube",
                    message: "Find videos, channels, and playlists."
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                    onDismissSearchPresentation()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(dismissSearchPresentationGesture)
        .onChange(of: model.submittedQuery) { _, _ in
            arePlaylistsExpanded = false
            areChannelsExpanded = true
            areVideosExpanded = true
        }
        .errorToast($model.errorState)
    }

    @ViewBuilder
    private func resultsList(_ results: SearchResult) -> some View {
        List {
            if !results.channels.isEmpty {
                Section {
                    if areChannelsExpanded {
                        ForEach(results.channels) { channel in
                            NavigationLink {
                                ChannelScreen(channelID: channel.id)
                            } label: {
                                ChannelRow(channel: channel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    collapsibleHeader("Channels", count: results.channels.count, isExpanded: $areChannelsExpanded)
                }
            }
            if !results.playlists.isEmpty {
                Section {
                    if arePlaylistsExpanded {
                        ForEach(results.playlists) { playlist in
                            NavigationLink {
                                PlaylistScreen(playlistID: playlist.id)
                            } label: {
                                PlaylistRow(playlist: playlist, showsMoreMenu: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            arePlaylistsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            Text("\(results.playlists.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: arePlaylistsExpanded ? "chevron.up" : "chevron.down")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !results.videos.isEmpty {
                Section {
                    if areVideosExpanded {
                        let lookaheadIDs = Set(results.videos.suffix(5).map(\.id))
                        ForEach(results.videos) { video in
                            VideoRow(
                                video: video,
                                showsMoreMenu: true,
                                offersPlayNext: true,
                                playbackProgress: progressByVideoID[video.id]
                            ) {
                                dismissKeyboard()
                                player.load(video)
                            }
                            .onAppear {
                                guard lookaheadIDs.contains(video.id),
                                      results.continuationToken != nil,
                                      !model.isLoading else { return }
                                Task { await model.loadMore() }
                            }
                        }
                    }
                    if model.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } header: {
                    collapsibleHeader("Videos", count: nil, isExpanded: $areVideosExpanded)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.refresh() }
        .task(id: progressLookupID(for: results.videos)) {
            await loadProgress(for: results.videos)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            Task { await loadProgress(for: results.videos) }
        }
    }

    private func collapsibleHeader(
        _ title: String,
        count: Int?,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let count {
                    Text("\(count)").foregroundStyle(.secondary)
                }
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    dismissKeyboard()
                    onDismissSearchPresentation()
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
            .scrollDismissesKeyboard(.immediately)
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
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// `.scrollDismissesKeyboard` resigns UIKit's first responder but does not consistently update
    /// `.searchable(isPresented:)` on iOS 26. End the native presentation after a real vertical
    /// content drag so the navigation title and search bar return to their matching idle state.
    private var dismissSearchPresentationGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissKeyboard()
                onDismissSearchPresentation()
            }
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
