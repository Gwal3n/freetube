import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class PlaylistViewModel {
    let playlistID: String
    private(set) var details: PlaylistDetails?
    private(set) var isLoading: Bool = false
    /// Separate flag so the row-level prefetch trigger doesn't fire while a previous
    /// `loadMore` is still in flight.
    private(set) var isLoadingMore: Bool = false
    private(set) var isSearchingPages = false
    private var searchSequence = 0
    private(set) var paginationFailed = false
    var errorState: ErrorState?

    private let service: any PlaylistServicing

    init(playlistID: String, service: any PlaylistServicing = PlaylistService()) {
        self.playlistID = playlistID
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        errorState = nil
        paginationFailed = false
        isLoading = true
        defer { isLoading = false }
        do {
            details = try await service.fetchPlaylist(id: playlistID)
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// True when the current page has a continuation token and no fetch is in flight.
    var canLoadMore: Bool {
        details?.continuationToken != nil && !isLoadingMore && !isLoading
    }

    /// Appends the next page of videos from the playlist's continuation. Replaces `details`
    /// with a new value (so `@Observable` notices), preserving the playlist header and the
    /// already-loaded videos.
    func loadMore() async {
        guard let current = details, let token = current.continuationToken, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        errorState = nil
        paginationFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await service.fetchMore(continuation: token)
            guard !Task.isCancelled else { return }
            details = PlaylistDetails(
                playlist: current.playlist,
                videos: current.videos + page.videos,
                continuationToken: page.continuationToken
            )
        } catch {
            guard !Task.isCancelled else { return }
            paginationFailed = true
            errorState = ErrorState(from: error)
        }
    }

    /// Public playlists have no server-side query endpoint. Load their remaining pages while a
    /// search is active, filtering locally as each page arrives. Stopping at the first match leaves
    /// later matching videos invisible and can make a playlist search appear incomplete.
    /// The screen owns cancellation when the query changes or disappears.
    func loadRemainingPagesForSearch(for query: String) async {
        guard !query.isEmpty, details != nil else { return }
        searchSequence &+= 1
        let sequence = searchSequence
        isSearchingPages = true
        defer {
            if searchSequence == sequence { isSearchingPages = false }
        }

        while !Task.isCancelled && searchSequence == sequence {
            guard let current = details,
                  let previousToken = current.continuationToken else { return }

            // The visible list may already be fetching its look-ahead page. Let that request
            // finish instead of racing two requests against the same continuation token.
            if isLoadingMore {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
                continue
            }

            await loadMore()
            guard !Task.isCancelled, searchSequence == sequence else { return }
            // A failed request or a repeated token must not spin on the same page forever.
            guard details?.continuationToken != previousToken else { return }
        }
    }

}
