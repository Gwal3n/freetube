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
