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
    private(set) var isUpdating = false
    private(set) var isLoadingSavedVideos = true
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var videos: [Video] = []
    private(set) var searchedQuery: String?
    private(set) var searchFailed = false
    private(set) var paginationFailed = false
    private(set) var continuationToken: String?
    private(set) var savedVideoIDs = Set<String>()
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

    func loadSavedVideos(in playlistID: String) async {
        defer { isLoadingSavedVideos = false }
        guard let details = await service.details(id: playlistID) else { return }
        savedVideoIDs = Set(details.videos.map(\.id))
    }

    func isSaved(_ video: Video) -> Bool { savedVideoIDs.contains(video.id) }

    var isCurrentInputSaved: Bool {
        guard let id = YouTubeVideoLink.videoID(from: query, allowBareID: true) else { return false }
        return savedVideoIDs.contains(id)
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

    func toggle(video: Video, in playlistID: String) async {
        guard !isUpdating, !isLoadingSavedVideos else { return }
        isUpdating = true
        errorState = nil
        defer { isUpdating = false }
        if savedVideoIDs.contains(video.id) {
            await service.remove(videoID: video.id, from: playlistID)
            savedVideoIDs.remove(video.id)
            return
        }
        do {
            try await service.addSearchedVideo(video, to: playlistID)
            savedVideoIDs.insert(video.id)
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// The one field searches phrases and toggles saved state for direct video references.
    func submit(to playlistID: String) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        guard let id = YouTubeVideoLink.videoID(from: term, allowBareID: true) else {
            await search()
            return
        }
        guard !isUpdating, !isLoadingSavedVideos else { return }
        errorState = nil
        if savedVideoIDs.contains(id) {
            isUpdating = true
            await service.remove(videoID: id, from: playlistID)
            savedVideoIDs.remove(id)
            isUpdating = false
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await service.addVideo(from: term, to: playlistID)
            savedVideoIDs.insert(id)
        } catch {
            errorState = ErrorState(from: error)
        }
    }
}
