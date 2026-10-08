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
    private(set) var isSearchingForMatch = false
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

    /// Search is local to this public playlist. Its endpoint offers continuation pages but no
    /// query parameter, so check later pages only when the loaded rows have no match. Stop as soon
    /// as a match appears; users can explicitly load more if they want additional matches. The
    /// caller owns cancellation when the field changes or the screen disappears.
    func loadUntilFirstMatch(for query: String) async {
        guard !query.isEmpty, details != nil else { return }
        searchSequence &+= 1
        let sequence = searchSequence
        isSearchingForMatch = true
        defer {
            if searchSequence == sequence { isSearchingForMatch = false }
        }

        while !Task.isCancelled {
            guard let current = details,
                  !current.videos.contains(where: {
                      $0.title.localizedStandardContains(query)
                          || $0.channelName.localizedStandardContains(query)
                  }),
                  let previousToken = current.continuationToken else { return }

            // The visible list may already be fetching its look-ahead page. Let that request
            // finish instead of racing two requests against the same continuation token.
            if isLoadingMore {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
                continue
            }

            await loadMore()
            guard details?.continuationToken != previousToken else { return }
        }
    }

}
