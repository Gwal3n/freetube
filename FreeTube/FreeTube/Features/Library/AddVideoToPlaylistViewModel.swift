import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class AddVideoToPlaylistViewModel {
    var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespacesAndNewlines) != searchedQuery {
                searchGeneration &+= 1
                videos = []
                continuationToken = nil
                searchedQuery = nil
                searchFailed = false
                isSearching = false
                isLoadingMore = false
            }
        }
    }
    var link = ""
    private(set) var isAdding = false
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var videos: [Video] = []
    private(set) var searchedQuery: String?
    private(set) var searchFailed = false
    private(set) var paginationFailed = false
    private(set) var continuationToken: String?
    var errorState: ErrorState?
    private let service: LocalPlaylistService
    private let searchService: any SearchServicing
    private let preferences = UserPreferences()
    private var searchGeneration = 0

    init(
        service: LocalPlaylistService = LocalPlaylistService(),
        searchService: any SearchServicing = SearchService()
    ) {
        self.service = service
        self.searchService = searchService
    }

    func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        searchedQuery = term
        videos = []
        continuationToken = nil
        searchFailed = false
        paginationFailed = false
        isSearching = true
        defer { if searchGeneration == generation { isSearching = false } }
        do {
            let result = try await searchService.search(query: term, restricted: preferences.restrictedSearchMode)
            guard searchGeneration == generation else { return }
            videos = result.videos
            continuationToken = result.continuationToken
        } catch {
            guard searchGeneration == generation else { return }
            searchFailed = true
            errorState = ErrorState(message: "Search couldn’t be completed. Please try again.")
        }
    }

    func loadMore() async {
        guard let token = continuationToken, !isSearching, !isLoadingMore else { return }
        let generation = searchGeneration
        isLoadingMore = true
        paginationFailed = false
        defer { if searchGeneration == generation { isLoadingMore = false } }
        do {
            let result = try await searchService.fetchMore(continuation: token)
            guard searchGeneration == generation else { return }
            let known = Set(videos.map(\.id))
            videos.append(contentsOf: result.videos.filter { !known.contains($0.id) })
            continuationToken = result.continuationToken
        } catch {
            guard searchGeneration == generation else { return }
            paginationFailed = true
            errorState = ErrorState(message: "More results couldn’t be loaded. Please try again.")
        }
    }

    func add(video: Video, to playlistID: String) async -> Bool {
        guard !isAdding else { return false }
        isAdding = true
        errorState = nil
        defer { isAdding = false }
        do {
            try await service.addSearchedVideo(video, to: playlistID)
            return true
        } catch {
            errorState = ErrorState(from: error)
            return false
        }
    }

    func addLink(to playlistID: String) async -> Bool {
        guard !isAdding else { return false }
        isAdding = true
        errorState = nil
        defer { isAdding = false }
        do {
            try await service.addVideo(from: link, to: playlistID)
            return true
        } catch {
            errorState = ErrorState(from: error)
            return false
        }
    }
}
