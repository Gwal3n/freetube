import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class PlaylistLoadingTests: XCTestCase {
    func testViewCountLabelIsNotUsedAsPlaylistChannel() {
        XCTAssertEqual(Mappers.channelName(from: "21K views"), "")
        XCTAssertEqual(Mappers.channelName(from: "Zeta Explained"), "Zeta Explained")
    }

    func testFailedLoadCanRetryAndClearsItsError() async {
        let service = RetryPlaylistService(failingAttempt: 1)
        let model = PlaylistViewModel(playlistID: "playlist", service: service)
        await model.load()
        XCTAssertNil(model.details)
        XCTAssertNotNil(model.errorState)
        XCTAssertFalse(model.isLoading)

        await model.load()
        XCTAssertEqual(model.details?.playlist.id, "playlist")
        XCTAssertNil(model.errorState)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(service.attempts, 2)
    }

    func testFailedReloadKeepsExistingContent() async {
        let model = PlaylistViewModel(playlistID: "playlist", service: RetryPlaylistService(failingAttempt: 2))
        await model.load()
        await model.load()
        XCTAssertEqual(model.details?.playlist.title, "Cached playlist")
        XCTAssertNotNil(model.errorState)
        XCTAssertFalse(model.isLoading)
    }

    func testPlaylistSearchContinuesPastFirstMatch() async {
        let service = PagedPlaylistService()
        let model = PlaylistViewModel(playlistID: "playlist", service: service)
        await model.load()

        // The first page already matches. Search still needs later pages, because they may
        // contain another matching video that should appear in the filtered results.
        await model.loadRemainingPagesForSearch(for: "match")

        XCTAssertEqual(service.requestedTokens, ["page-2", "page-3"])
        XCTAssertEqual(model.details?.videos.map(\.title), ["First match", "Other", "Last match"])
        XCTAssertNil(model.details?.continuationToken)
        XCTAssertFalse(model.isSearchingPages)
    }

    func testHistoryRestoresVideoBeyondFirstPlaylistPage() async throws {
        let service = PagedPlaylistService()
        let restoration = HistoryPlaylistRestorationService(remotePlaylists: service)
        let entry = WatchHistorySnapshot(
            videoID: "last",
            title: "Last match",
            channelName: "Channel",
            channelID: nil,
            thumbnailURL: nil,
            watchedAt: .now,
            lastPosition: 60,
            duration: 240,
            playlistID: "playlist",
            playlistTitle: "Playlist",
            playlistOriginRaw: PlaylistPlaybackOrigin.youtube.rawValue
        )

        let details = try await restoration.restore(for: entry)

        XCTAssertEqual(details?.videos.map(\.id), ["first", "middle", "last"])
        XCTAssertNil(details?.continuationToken)
        XCTAssertEqual(service.requestedTokens, ["page-2", "page-3"])
    }
}

@MainActor
private final class PagedPlaylistService: PlaylistServicing {
    private(set) var requestedTokens: [String] = []

    func fetchPlaylist(id: String) async throws -> PlaylistDetails {
        PlaylistDetails(
            playlist: Playlist(
                id: id, title: "Playlist", channelID: nil, channelName: nil,
                thumbnailURL: nil, videoCount: 3, descriptionText: nil, isOwnedByUser: false
            ),
            videos: [video(id: "first", title: "First match")],
            continuationToken: "page-2"
        )
    }

    func fetchMore(continuation: String) async throws -> PlaylistDetails {
        requestedTokens.append(continuation)
        switch continuation {
        case "page-2":
            return PlaylistDetails(
                playlist: placeholder,
                videos: [video(id: "middle", title: "Other")],
                continuationToken: "page-3"
            )
        case "page-3":
            return PlaylistDetails(
                playlist: placeholder,
                videos: [video(id: "last", title: "Last match")],
                continuationToken: nil
            )
        default:
            throw URLError(.badServerResponse)
        }
    }

    private var placeholder: Playlist {
        Playlist(
            id: "", title: "", channelID: nil, channelName: nil,
            thumbnailURL: nil, videoCount: nil, descriptionText: nil, isOwnedByUser: false
        )
    }

    private func video(id: String, title: String) -> Video {
        Video(
            id: id, title: title, channelID: "", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil, duration: nil, viewCount: nil,
            publishedAt: nil, descriptionSnippet: nil, isLive: false, isShort: false
        )
    }
}

@MainActor
private final class RetryPlaylistService: PlaylistServicing {
    let failingAttempt: Int
    private(set) var attempts = 0

    init(failingAttempt: Int) { self.failingAttempt = failingAttempt }

    func fetchPlaylist(id: String) async throws -> PlaylistDetails {
        attempts += 1
        if attempts == failingAttempt { throw URLError(.notConnectedToInternet) }
        return PlaylistDetails(
            playlist: Playlist(
                id: id, title: "Cached playlist", channelID: nil, channelName: nil,
                thumbnailURL: nil, videoCount: 0, descriptionText: nil, isOwnedByUser: false
            ),
            videos: [], continuationToken: nil
        )
    }

    func fetchMore(continuation: String) async throws -> PlaylistDetails {
        throw URLError(.badServerResponse)
    }
}
