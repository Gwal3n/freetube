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
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var searchModel = SearchViewModel()
    @State private var path: [AppNavigationRequest.Destination] = []
    @State private var isSearchPresented = false
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerStateManager.self) private var player
    private let navigationLog = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

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

                SearchContent(
                    model: searchModel,
                    onRunSearch: { query in
                        Task { await runSearch(query: query) }
                    },
                    onOpenDestination: openDestination
                )
            }
            .contentShape(Rectangle())
            .navigationTitle("Search")
            .modifier(ConditionalSearchable(
                text: $searchModel.query,
                isPresented: $isSearchPresented,
                enabled: !MacIntegration.isRunningOnMac,
                prompt: "Search YouTube"
            ))
            .navigationDestination(for: AppNavigationRequest.Destination.self) { destination in
                switch destination {
                case .channel(let id):
                    ChannelScreen(channelID: id)
                        .onAppear { navigationLog.info("Search channel destination appeared") }
                case .playlist(let id):
                    PlaylistScreen(playlistID: id)
                        .onAppear { navigationLog.info("Search playlist destination appeared: \(id, privacy: .public)") }
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                navigationLog.info("Search keyboard shown; presented=\(isSearchPresented, privacy: .public)")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                navigationLog.info("Search keyboard hidden; presented=\(isSearchPresented, privacy: .public)")
                // `.searchable(isPresented:)` does not always clear its presentation binding when
                // UIKit dismisses the keyboard interactively. Leaving it true pins the expanded
                // search drawer at the top even though search is no longer active.
                isSearchPresented = false
            }
            .onChange(of: isSearchPresented) { _, isPresented in
                navigationLog.info("Search presentation changed: \(isPresented, privacy: .public)")
            }
            .onChange(of: path) { oldPath, newPath in
                navigationLog.info("Search path changed: \(oldPath.count, privacy: .public) → \(newPath.count, privacy: .public)")
            }
            // Clearing the field returns to recent searches (or the clean empty state).
            .onChange(of: searchModel.query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchModel.clearResults()
                }
            }
            .onChange(of: navigationRouter.search?.id, initial: true) { _, _ in
                guard let request = navigationRouter.search else { return }
                navigationRouter.search = nil
                navigationLog.info("Search received player destination")
                openDestination(request.destination)
            }
        }
    }

    /// Native searchable owns a presentation layer above the navigation stack. Pushing while
    /// that layer is active can make iOS 26 reopen/focus the field and discard the destination.
    /// End search first, let that transaction settle, then perform the stack mutation.
    private func openDestination(_ destination: AppNavigationRequest.Destination) {
        navigationLog.info("Search destination requested: \(String(describing: destination), privacy: .public)")
        isSearchPresented = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        Task { @MainActor in
            await Task.yield()
            guard path.last != destination else {
                navigationLog.info("Search destination already current")
                return
            }
            path.append(destination)
            navigationLog.info("Search destination appended; path count=\(path.count, privacy: .public)")
        }
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
        // Respond immediately; network completion must not later dismiss a keyboard the user
        // has reopened to edit a different query.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if let existing = history.first(where: { $0.query == trimmed }) {
            existing.searchedAt = .now
        } else {
            modelContext.insert(SearchHistoryEntry(query: trimmed))
        }
        try? modelContext.save()
        if let directVideo = searchModel.directVideo(from: trimmed) {
            searchModel.clearResults()
            isSearchPresented = false
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

}
