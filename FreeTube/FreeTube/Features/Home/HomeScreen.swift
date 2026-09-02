import SwiftUI
import SwiftData

/// **Search** tab. Search suggestions, results, and local recent searches only; it deliberately
/// performs no home/trending feed request while idle.
///
/// Mac uses an inline field because `.searchable` collapses awkwardly there. iPhone and iPad use
/// native `.searchable`, preserving the system Liquid Glass presentation.
@available(iOS 17.0, *)
struct HomeScreen: View {
    @State private var searchModel = SearchViewModel()
    @State private var path = NavigationPath()
    @State private var isSearchPresented = false
    @Environment(\.modelContext) private var modelContext

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

                SearchContent(model: searchModel) {
                    Task { await runSearch() }
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
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            // Clearing the field returns to recent searches (or the clean empty state).
            .onChange(of: searchModel.query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchModel.clearResults()
                }
            }
            .refreshable {
                if searchModel.results != nil {
                    await searchModel.submit()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .freetubeFocusSearch)) { _ in
                guard !MacIntegration.isRunningOnMac else { return }
                path = NavigationPath()
                isSearchPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenChannel)) { note in
                guard let channelID = note.object as? String, !channelID.isEmpty else { return }
                path.append(SearchChannelRoute(id: channelID))
            }
        }
    }

    /// Persists the trimmed query to history (upsert by query string) then fires
    /// `searchModel.submit()`. Same logic the dedicated Search tab used to run.
    private func runSearch() async {
        let trimmed = searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = history.first(where: { $0.query == trimmed }) {
            existing.searchedAt = .now
        } else {
            modelContext.insert(SearchHistoryEntry(query: trimmed))
        }
        try? modelContext.save()
        await searchModel.submit()
    }
}

private struct SearchChannelRoute: Hashable {
    let id: String
}
