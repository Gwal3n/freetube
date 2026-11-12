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
    private enum CustomRange: String, Identifiable {
        case uploaded, length, views
        var id: String { rawValue }
    }

    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var searchModel = SearchViewModel()
    @State private var path: [AppNavigationRequest.Destination] = []
    @State private var isSearchPresented = false
    /// Submitted query to restore if ending native search presentation clears the field text.
    @State private var queryPreservedDuringDismissal: String?
    @State private var customRange: CustomRange?
    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("incognitoHideLibrary") private var incognitoHideLibrary = false
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
                    onOpenDestination: openDestination,
                    onCustomUploaded: { customRange = .uploaded },
                    onCustomLength: { customRange = .length },
                    onCustomViews: { customRange = .views }
                )
            }
            .contentShape(Rectangle())
            .navigationTitle("Search")
            .toolbar {
                if incognitoEnabled && incognitoHideLibrary {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            NotificationCenter.default.post(name: .freetubeOpenSettings, object: nil)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(item: $customRange) { range in
                switch range {
                case .uploaded:
                    SearchDateRangeSheet(range: searchModel.videoFilters.customUploadedRange) { selected in
                        searchModel.videoFilters.customUploadedRange = selected
                        searchModel.videoFilters.uploaded = .custom
                    }
                case .length:
                    SearchNumericRangeSheet(
                        kind: .duration,
                        range: searchModel.videoFilters.customLengthRange
                    ) { selected in
                        searchModel.videoFilters.customLengthRange = selected
                        searchModel.videoFilters.length = .custom
                    }
                case .views:
                    SearchNumericRangeSheet(
                        kind: .views,
                        range: searchModel.videoFilters.customViewsRange
                    ) { selected in
                        searchModel.videoFilters.customViewsRange = selected
                        searchModel.videoFilters.views = .custom
                    }
                }
            }
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
            .onChange(of: isSearchPresented) { _, isPresented in
                navigationLog.info("Search presentation changed: \(isPresented, privacy: .public)")
                if isPresented {
                    queryPreservedDuringDismissal = nil
                }
            }
            .onChange(of: path) { oldPath, newPath in
                navigationLog.info("Search path changed: \(oldPath.count, privacy: .public) → \(newPath.count, privacy: .public)")
            }
            // Clearing the field returns to recent searches (or the clean empty state).
            .onChange(of: searchModel.query) { _, newValue in
                guard newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                if let preserved = queryPreservedDuringDismissal {
                    searchModel.query = preserved
                    return
                }
                searchModel.clearResults()
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
        if let submitted = searchModel.submittedQuery, !searchModel.isEditingNewQuery {
            endActiveSearch(preserving: submitted)
        } else {
            isSearchPresented = false
        }
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
        if UserPreferences().recordsSearchHistory {
            if let existing = history.first(where: { $0.query == trimmed }) {
                existing.searchedAt = .now
            } else {
                modelContext.insert(SearchHistoryEntry(query: trimmed))
            }
            try? modelContext.save()
        }
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
        // Stock behavior: search stays active after submission, with the query and Cancel button
        // in the field. Only the keyboard is dismissed (above).
        await searchModel.submit()
    }

    /// Ends native search presentation while keeping `query` in the field, used before pushing a
    /// destination. SwiftUI may clear the bound text as part of that transition; the guard window
    /// restores it instead of treating it as the user's clear action. Later clears behave normally.
    private func endActiveSearch(preserving query: String) {
        queryPreservedDuringDismissal = query
        isSearchPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if queryPreservedDuringDismissal == query {
                queryPreservedDuringDismissal = nil
            }
        }
    }

}
