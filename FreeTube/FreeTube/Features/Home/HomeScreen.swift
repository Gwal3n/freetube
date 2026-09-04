import SwiftUI
import SwiftData
import UIKit

/// **Search** tab. Search suggestions, results, and local recent searches only; it deliberately
/// performs no home/trending feed request while idle.
///
/// Mac uses an inline field because `.searchable` collapses awkwardly there. iPhone and iPad use
/// native `.searchable`, preserving the system Liquid Glass presentation.
@available(iOS 17.0, *)
struct HomeScreen: View {
    let searchActivation: Int
    @State private var searchModel = SearchViewModel()
    @State private var path = NavigationPath()
    @State private var isSearchPresented = false
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerStateManager.self) private var player

    /// Recent search queries — same store the previous Search tab used. Stays here so the
    /// host can do the upsert in `runSearch` (the field's submit fires on this view).
    @Query(sort: \SearchHistoryEntry.searchedAt, order: .reverse) private var history: [SearchHistoryEntry]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if MacIntegration.isRunningOnMac {
                    MacInlineSearchField(query: $searchModel.query) {
                        Task { await runSearch() }
                    }
                }

                SearchContent(model: searchModel) { query in
                    Task { await runSearch(query: query) }
                }
            }
            .navigationTitle("Search")
            .modifier(ConditionalSearchable(
                text: $searchModel.query,
                isPresented: $isSearchPresented,
                enabled: !MacIntegration.isRunningOnMac,
                prompt: "Search YouTube"
            ))
            .navigationDestination(for: SearchChannelRoute.self) { route in
                ChannelScreen(channelID: route.id)
            }
            .toolbar {
                if searchModel.submittedQuery != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            leaveSearchResults()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
            }
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            // Clearing the field returns to recent searches (or the clean empty state).
            .onChange(of: searchModel.query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchModel.clearResults()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenChannel)) { note in
                guard let channelID = note.object as? String, !channelID.isEmpty else { return }
                path.append(SearchChannelRoute(id: channelID))
            }
            .onChange(of: searchActivation) { _, _ in
                guard !MacIntegration.isRunningOnMac else { return }
                // Re-selecting Search returns from a pushed destination and focuses the native
                // field in one action. It must not discard the current term or result set.
                if !path.isEmpty {
                    path = NavigationPath()
                }
                Task { @MainActor in
                    await Task.yield()
                    await focusSearch()
                }
            }
        }
    }

    /// Gives focus back to native `.searchable` without coupling presentation to query/results.
    private func focusSearch() async {
        // Native searchable can remain logically presented after its keyboard resigns. Cycle only
        // the presentation binding on an explicit tab re-tap so it reliably regains first responder
        // without coupling ordinary keyboard dismissal to navigation-bar layout.
        if isSearchPresented {
            isSearchPresented = false
            await Task.yield()
        }
        isSearchPresented = true
    }

    /// Persists the trimmed query, then either opens a recognized YouTube URL or performs search.
    private func runSearch() async {
        await runSearch(query: searchModel.query)
    }

    /// Runs the explicitly selected value so row taps cannot race focus or presentation updates.
    private func runSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchModel.query = trimmed
        if let existing = history.first(where: { $0.query == trimmed }) {
            existing.searchedAt = .now
        } else {
            modelContext.insert(SearchHistoryEntry(query: trimmed))
        }
        try? modelContext.save()
        if let directVideo = searchModel.directVideo(from: trimmed) {
            searchModel.clearResults()
            player.load(directVideo)
            // Give the resolution task created by `load` the first opportunity to start. Metadata
            // is useful polish, but it must remain behind the playback-critical request.
            await Task.yield()
            if let metadata = await searchModel.metadata(forDirectVideoID: directVideo.id) {
                player.enrichCurrentVideo(with: metadata)
            }
            return
        }
        await searchModel.submit()
    }

    /// Returns to the recent-search root without a navigation transition. The same native search
    /// field stays mounted; only its query and the result content are reset.
    private func leaveSearchResults() {
        searchModel.query = ""
        searchModel.clearResults()
        isSearchPresented = false
    }
}

private struct SearchChannelRoute: Hashable {
    let id: String
}
