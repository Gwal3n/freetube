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
    private(set) var isLoading: Bool = false
    var errorState: ErrorState?

    private let service: any SearchServicing
    private let videoService: any VideoServicing
    private let preferences = UserPreferences()
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SearchViewModel")

    private var autocompleteTask: Task<Void, Never>?
    private var searchGeneration = 0

    /// True while the field contains a new query that has not produced the visible result set.
    /// SearchContent uses this to show live suggestions instead of stale results.
    var isEditingNewQuery: Bool {
        let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return current != submittedQuery
    }

    init(
        service: any SearchServicing = SearchService(),
        videoService: any VideoServicing = VideoService()
    ) {
        self.service = service
        self.videoService = videoService
    }

    /// Returns an immediately playable seed for supported YouTube URLs. Metadata is deliberately
    /// filled in separately so parsing a pasted URL never adds a blocking request before playback.
    func directVideo(from text: String) -> Video? {
        guard let id = Self.youtubeVideoID(from: text) else { return nil }
        return Video(
            id: id,
            title: "YouTube video",
            channelID: "",
            channelName: "YouTube",
            channelThumbnailURL: nil,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            duration: nil,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
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
        autocompleteTask?.cancel()
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
            let result = try await service.search(query: submittedQuery, restricted: preferences.restrictedSearchMode)
            guard searchGeneration == generation,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery
            else { return }
            results = result
            self.submittedQuery = submittedQuery
            suggestions = []
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func loadMore() async {
        guard let token = results?.continuationToken, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await service.fetchMore(continuation: token)
            let mergedVideos = (results?.videos ?? []) + next.videos
            let mergedChannels = (results?.channels ?? []) + next.channels
            let mergedPlaylists = (results?.playlists ?? []) + next.playlists
            results = SearchResult(
                videos: mergedVideos,
                channels: mergedChannels,
                playlists: mergedPlaylists,
                continuationToken: next.continuationToken
            )
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// Refreshes the submitted query without removing the visible List, allowing the native
    /// pull-to-refresh indicator to remain attached throughout the request.
    func refresh() async {
        guard let submittedQuery else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        isLoading = true
        defer { if searchGeneration == generation { isLoading = false } }
        do {
            let refreshed = try await service.search(
                query: submittedQuery,
                restricted: preferences.restrictedSearchMode
            )
            guard searchGeneration == generation else { return }
            results = refreshed
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    private func scheduleAutocomplete() {
        autocompleteTask?.cancel()
        let snapshot = query
        autocompleteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runAutocomplete(snapshot)
        }
    }

    private func runAutocomplete(_ q: String) async {
        guard !Task.isCancelled, q == query else { return }
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

    private static func youtubeVideoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let candidate: String
        if lowercased.hasPrefix("youtube.com/")
            || lowercased.hasPrefix("www.youtube.com/")
            || lowercased.hasPrefix("m.youtube.com/")
            || lowercased.hasPrefix("music.youtube.com/")
            || lowercased.hasPrefix("youtu.be/") {
            candidate = "https://" + trimmed
        } else {
            candidate = trimmed
        }

        guard let components = URLComponents(string: candidate),
              let rawHost = components.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let pathParts = components.path.split(separator: "/").map(String.init)
        let possibleID: String?

        if host == "youtu.be" {
            possibleID = pathParts.first
        } else if host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com") {
            if components.path == "/watch" {
                possibleID = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if let route = pathParts.first?.lowercased(),
                      ["shorts", "embed", "live"].contains(route),
                      pathParts.count > 1 {
                possibleID = pathParts[1]
            } else {
                possibleID = nil
            }
        } else {
            possibleID = nil
        }

        guard let id = possibleID, id.count == 11 else { return nil }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        guard id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return id
    }
}
