import SwiftUI
import SwiftData
import UIKit

/// Renders search results, suggestions, history, and the empty state. `HomeScreen` owns the search
/// presentation and the history-upsert submit callback.
@available(iOS 17.0, *)
struct SearchContent: View {
    @Bindable var model: SearchViewModel
    let onRunSearch: (String) -> Void
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.modelContext) private var modelContext

    /// Recently entered search queries, newest first. Tapping one re-runs the search.
    @Query(sort: \SearchHistoryEntry.searchedAt, order: .reverse) private var history: [SearchHistoryEntry]

    var body: some View {
        Group {
            if let results = model.results {
                resultsList(results)
            } else if !model.suggestions.isEmpty {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Observe only this container's empty-area taps. Including subviews here can consume native
        // List row buttons, including recent-search selection.
        .simultaneousGesture(
            TapGesture().onEnded { dismissKeyboard() },
            including: .gesture
        )
        .errorToast($model.errorState)
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

    @ViewBuilder
    private func resultsList(_ results: SearchResult) -> some View {
        List {
            if !results.channels.isEmpty {
                Section("Channels") {
                    ForEach(results.channels) { channel in
                        NavigationLink {
                            ChannelScreen(channelID: channel.id)
                        } label: {
                            ChannelRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(results.playlists) { playlist in
                        NavigationLink {
                            PlaylistScreen(playlistID: playlist.id)
                        } label: {
                            PlaylistRow(playlist: playlist, showsMoreMenu: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.videos.isEmpty {
                Section("Videos") {
                    let lookaheadIDs = Set(results.videos.suffix(5).map(\.id))
                    ForEach(results.videos) { video in
                        VideoRow(video: video, showsMoreMenu: true) {
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
                    if model.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
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
