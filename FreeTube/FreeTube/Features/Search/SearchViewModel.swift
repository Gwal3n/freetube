import Foundation
import Observation
import OSLog

@available(iOS 17.0, *)
@Observable
@MainActor
final class SearchViewModel {
    var query: String = "" {
        didSet {
            suggestions = []
            scheduleAutocomplete()
        }
    }
    private(set) var submittedQuery: String?
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: SearchResult?
    /// Advances only when a new first page replaces the results, not for continuation pages.
    /// Filtered-result fill tasks use this to start once per search/refresh with a fixed budget.
    private(set) var resultsRevision = 0
    private(set) var isLoading: Bool = false
    private(set) var didSearchFail = false
    private(set) var paginationFailed = false
    var errorState: ErrorState?
    /// When `true`, upload/length presets that normally ride on InnerTube `params` are also
    /// enforced locally (plain-query fallback, or no server params active).
    private(set) var applyServerMirroredLocally = true
    /// Presentation filters for the current result set. Reset whenever a new query is submitted
    /// or results are cleared. Changing server-backed fields re-runs the search via
    /// `serverFiltersDidChange(from:)`.
    var videoFilters = SearchVideoFilters()
    /// Local watch history for the current result page. Owned here so filter fill and row chrome
    /// share one PersistenceWriter pass instead of living in the view.
    private(set) var progressByVideoID: [String: Double] = [:]
    private(set) var watchStatusByVideoID: [String: WatchHistoryStatus] = [:]

    private let service: any SearchServicing
    private let musicService: any MusicSearchServicing
    private let videoService: any VideoServicing
    private let preferences = UserPreferences()
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SearchViewModel")

    private var autocompleteTask: Task<Void, Never>?
    private var searchGeneration = 0
    /// Dedupes filtered-page prefetch after an explicit Load more / lookahead.
    private var lastFilteredPrefetch: FilteredPrefetchKey?

    /// True while the field contains a new query that has not produced the visible result set.
    /// SearchContent uses this to show live suggestions instead of stale results.
    var isEditingNewQuery: Bool {
        let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return current != submittedQuery
    }

    init(
        service: any SearchServicing = SearchService(),
        musicService: any MusicSearchServicing = MusicSearchService(),
        videoService: any VideoServicing = VideoService()
    ) {
        self.service = service
        self.musicService = musicService
        self.videoService = videoService
    }

    /// Returns an immediately playable seed for supported YouTube URLs. Metadata is deliberately
    /// filled in separately so parsing a pasted URL never adds a blocking request before playback.
    func directVideo(from text: String) -> Video? {
        guard let id = YouTubeVideoLink.videoID(from: text) else { return nil }
        return YouTubeVideoLink.playbackSeed(for: id)
    }

    func metadata(forDirectVideoID id: String) async -> Video? {
        do {
            let video = try await videoService.fetchInfo(id: id).video
            return video.title.isEmpty ? nil : video
        } catch {
            log.notice("Direct URL metadata lookup failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Drops the previous search's results + suggestions so the embedding view can fall
    /// back to its non-search state. Called when the search field is cleared.
    func clearResults() {
        searchGeneration &+= 1
        results = nil
        submittedQuery = nil
        suggestions = []
        isLoading = false
        didSearchFail = false
        paginationFailed = false
        errorState = nil
        progressByVideoID = [:]
        watchStatusByVideoID = [:]
        lastFilteredPrefetch = nil
        resetFilters()
        autocompleteTask?.cancel()
    }

    /// Whether a hit survives the current result-type / video filters. Blocking stays call-site owned.
    func includes(_ hit: SearchHit, now: Date = .now, status: WatchHistoryStatus?) -> Bool {
        let resultType = videoFilters.resultType
        switch hit {
        case .video(let video):
            guard resultType == .any || resultType == .video else { return false }
            guard videoFilters.isActive else { return true }
            return videoFilters.includes(
                video,
                status: status,
                now: now,
                applyServerMirroredLocally: applyServerMirroredLocally
            )
        case .channel:
            return resultType == .any || resultType == .channel
        case .playlist:
            return resultType == .any || resultType == .playlist
        }
    }

    func watchStatus(for hit: SearchHit) -> WatchHistoryStatus? {
        guard case .video(let video) = hit else { return nil }
        return watchStatusByVideoID[video.id]
    }

    func loadWatchProgress(for videos: [Video]) async {
        let ids = videos.map(\.id)
        let summary = await PersistenceWriter.shared.watchHistorySummary(videoIDs: ids)
        guard !Task.isCancelled, results?.videos.map(\.id) == ids else { return }
        watchStatusByVideoID = summary.statuses
        progressByVideoID = preferences.displaysWatchProgress ? summary.progress : [:]
    }

    /// Fill a sparse filtered list without turning a very narrow filter into an unlimited stream
    /// of YouTube requests. A later explicit Load more starts another bounded batch.
    func fillFilteredResults(
        autoLoadMore: Bool,
        blockingActive: Bool,
        isBlocked: @escaping (SearchHit) -> Bool
    ) async {
        guard autoLoadMore else { return }
        let filters = videoFilters
        guard filters.isActive || blockingActive, let query = submittedQuery else { return }
        let revision = resultsRevision
        let targetCount = 12
        let maximumPages = 6

        for _ in 0..<maximumPages {
            while isLoading {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            guard !Task.isCancelled,
                  filters == videoFilters,
                  resultsRevision == revision,
                  submittedQuery == query,
                  !isEditingNewQuery,
                  !paginationFailed,
                  let current = results,
                  let token = current.continuationToken else { return }

            let statuses: [String: WatchHistoryStatus]
            if filters.watch == .all {
                statuses = [:]
            } else {
                let summary = await PersistenceWriter.shared.watchHistorySummary(
                    videoIDs: current.videos.map(\.id)
                )
                guard !Task.isCancelled, filters == videoFilters,
                      resultsRevision == revision else { return }
                statuses = summary.statuses
            }
            let now = Date.now
            let visibleCount = current.items.filter { hit in
                !isBlocked(hit) && includes(hit, now: now, status: {
                    guard case .video(let video) = hit else { return nil }
                    return statuses[video.id]
                }())
            }.count
            if visibleCount >= targetCount { return }

            await loadMore()
            guard !Task.isCancelled, results?.continuationToken != token else { return }
        }
    }

    /// Records a filtered prefetch key so lookahead does not re-fire for the same page size.
    func shouldPrefetchFilteredPage(loadedCount: Int, blockingRevision: Int) -> Bool {
        let key = FilteredPrefetchKey(
            resultsRevision: resultsRevision,
            filters: videoFilters,
            blockingRevision: blockingRevision,
            loadedCount: loadedCount
        )
        guard lastFilteredPrefetch != key else { return false }
        lastFilteredPrefetch = key
        return true
    }

    func invalidateFilteredPrefetch() {
        lastFilteredPrefetch = nil
    }

    func submit() async {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        // A pending autocomplete request must never win the race with an explicit keyboard or
        // suggestion submission and put suggestions back over the requested results.
        if query != submittedQuery {
            query = submittedQuery
        }
        autocompleteTask?.cancel()
        suggestions = []
        results = nil
        progressByVideoID = [:]
        watchStatusByVideoID = [:]
        errorState = nil
        didSearchFail = false
        paginationFailed = false
        resetFilters()
        self.submittedQuery = submittedQuery
        isLoading = true
        defer {
            if searchGeneration == generation {
                isLoading = false
                if isEditingNewQuery {
                    scheduleAutocomplete()
                }
            }
        }
        do {
            let result = try await fetchFirstPage(query: submittedQuery, generation: generation)
            guard searchGeneration == generation,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery
            else { return }
            results = result
            resultsRevision &+= 1
            self.submittedQuery = submittedQuery
            suggestions = []
        } catch {
            guard searchGeneration == generation,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery else { return }
            didSearchFail = true
            log.notice("Search failed: \(String(describing: error), privacy: .public)")
            errorState = ErrorState(message: "Search couldn’t be completed. Please try again.")
        }
    }

    func loadMore() async {
        guard let current = results, let token = current.continuationToken, !isLoading else { return }
        let generation = searchGeneration
        errorState = nil
        paginationFailed = false
        isLoading = true
        defer { if searchGeneration == generation { isLoading = false } }
        do {
            let next = try await service.fetchMore(continuation: token)
            guard searchGeneration == generation else { return }
            let known = Set(current.items.map(\.id))
            let appended = next.items.filter { !known.contains($0.id) }
            results = SearchResult(
                items: current.items + appended,
                continuationToken: next.continuationToken
            )
        } catch {
            guard searchGeneration == generation else { return }
            paginationFailed = true
            log.notice("Loading more search results failed: \(String(describing: error), privacy: .public)")
            errorState = ErrorState(message: "More results couldn’t be loaded. Please try again.")
        }
    }

    /// Refreshes the submitted query without removing the visible List, allowing the native
    /// pull-to-refresh indicator to remain attached throughout the request.
    func refresh() async {
        guard let submittedQuery else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        errorState = nil
        paginationFailed = false
        isLoading = true
        defer { if searchGeneration == generation { isLoading = false } }
        do {
            let refreshed = try await fetchFirstPage(query: submittedQuery, generation: generation)
            guard searchGeneration == generation else { return }
            results = refreshed
            resultsRevision &+= 1
        } catch {
            guard searchGeneration == generation else { return }
            log.notice("Refreshing search failed: \(String(describing: error), privacy: .public)")
            errorState = ErrorState(message: "Search results couldn’t be refreshed. Please try again.")
        }
    }

    /// Re-runs search when server-backed filters change; ignores local-only edits and empty results.
    func serverFiltersDidChange(from oldValue: SearchVideoFilters) {
        guard oldValue.serverRequestKey != videoFilters.serverRequestKey else { return }
        guard submittedQuery != nil, results != nil, !isEditingNewQuery else { return }
        Task { await reloadForServerFilters() }
    }

    /// Re-runs the current query after a server-backed filter change. Keeps the list mounted so
    /// local-only filters can keep trimming without a flash back to history.
    private func reloadForServerFilters() async {
        guard let submittedQuery else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        let paramsSnapshot = videoFilters.serverParams
        let requestSnapshot = videoFilters.serverRequestKey
        errorState = nil
        paginationFailed = false
        didSearchFail = false
        isLoading = true
        defer { if searchGeneration == generation { isLoading = false } }
        do {
            let refreshed = try await fetchFirstPage(
                query: submittedQuery,
                generation: generation,
                params: paramsSnapshot
            )
            guard searchGeneration == generation,
                  videoFilters.serverRequestKey == requestSnapshot else { return }
            results = refreshed
            resultsRevision &+= 1
        } catch {
            guard searchGeneration == generation else { return }
            log.notice("Server-filter search failed: \(String(describing: error), privacy: .public)")
            errorState = ErrorState(message: "Search couldn’t be completed. Please try again.")
        }
    }

    /// Tries InnerTube `params` when present; on failure retries the plain query and mirrors
    /// those presets locally instead of asking the user to flip a mode switch.
    private func fetchFirstPage(
        query: String,
        generation: Int,
        params: String? = nil
    ) async throws -> SearchResult {
        if videoFilters.source == .music {
            applyServerMirroredLocally = true
            return try await musicService.search(query: query)
        }
        let resolvedParams = params ?? videoFilters.serverParams
        guard let resolvedParams else {
            applyServerMirroredLocally = true
            return try await service.search(query: query, params: nil)
        }
        do {
            let result = try await service.search(query: query, params: resolvedParams)
            guard searchGeneration == generation else { return result }
            applyServerMirroredLocally = false
            return result
        } catch {
            log.notice(
                "Server search params failed; falling back to plain query: \(String(describing: error), privacy: .public)"
            )
            let result = try await service.search(query: query, params: nil)
            guard searchGeneration == generation else { return result }
            applyServerMirroredLocally = true
            errorState = ErrorState(message: "Server filters unavailable. Using local filters.")
            return result
        }
    }

    private func resetFilters() {
        videoFilters = videoFilters.resettingFilters()
        applyServerMirroredLocally = true
        lastFilteredPrefetch = nil
    }

    private func scheduleAutocomplete() {
        autocompleteTask?.cancel()
        guard preferences.showSearchSuggestions else {
            suggestions = []
            return
        }
        let snapshot = query
        autocompleteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runAutocomplete(snapshot)
        }
    }

    private func runAutocomplete(_ q: String) async {
        guard !Task.isCancelled, q == query else { return }
        guard preferences.showSearchSuggestions else {
            suggestions = []
            return
        }
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            suggestions = []
            return
        }
        do {
            let fetched = try await service.autocomplete(query: q)
            guard !Task.isCancelled, q == query, !isLoading else { return }
            suggestions = fetched
        } catch {
            // Autocomplete failures are silent.
            log.debug("Autocomplete failed: \(String(describing: error), privacy: .public)")
        }
    }
}

@available(iOS 17.0, *)
private struct FilteredPrefetchKey: Equatable {
    let resultsRevision: Int
    let filters: SearchVideoFilters
    let blockingRevision: Int
    let loadedCount: Int
}
