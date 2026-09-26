import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class ChannelLoadingTests: XCTestCase {
    func testFailureRemainsRecoverableAfterToastDismissal() async {
        let service = ChannelLoadingFixture()
        let model = ChannelViewModel(channelID: "test-channel", service: service)
        await model.load()
        XCTAssertTrue(model.initialLoadFailed)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.details)

        model.errorState = nil
        XCTAssertTrue(model.initialLoadFailed)
        service.allowSuccess()
        await model.load()
        XCTAssertFalse(model.initialLoadFailed)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorState)
        XCTAssertEqual(model.details?.channel.id, "test-channel")
    }

    func testCancellationIsNotPresentedAsFailure() async {
        let service = ChannelLoadingFixture()
        service.cancelRequests()
        let model = ChannelViewModel(channelID: "test-channel", service: service)
        await model.load()
        XCTAssertFalse(model.initialLoadFailed)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorState)
        XCTAssertNil(model.details)
    }
}

@MainActor
private final class ChannelLoadingFixture: ChannelServicing {
    private var succeeds = false
    private var cancels = false

    func allowSuccess() { succeeds = true }
    func cancelRequests() { cancels = true }

    func fetchChannel(id: String) async throws -> ChannelDetails {
        if cancels { throw CancellationError() }
        guard succeeds else { throw URLError(.notConnectedToInternet) }
        return ChannelDetails(
            channel: Channel(id: id, name: "Test", handle: nil, thumbnailURL: nil,
                             bannerURL: nil, subscriberCount: nil, videoCount: nil,
                             isSubscribed: false, descriptionText: nil),
            videos: ChannelTab(items: [], continuationToken: nil),
            shorts: ChannelTab(items: [], continuationToken: nil),
            directs: ChannelTab(items: [], continuationToken: nil),
            playlists: ChannelTab(items: [], continuationToken: nil)
        )
    }

    func fetchChannelMetadata(id: String) async throws -> Channel { throw URLError(.unsupportedURL) }
    func fetchLatestVideos(channelID: String) async throws -> [Video] { throw URLError(.unsupportedURL) }
    func fetchVideos(channelID: String, sort: ChannelVideoSort) async throws -> ChannelTab<Video> {
        throw URLError(.unsupportedURL)
    }
    func fetchVideosNextPage(channelID: String, sort: ChannelVideoSort) async throws -> ChannelTab<Video> {
        throw URLError(.unsupportedURL)
    }
    func fetchVideosNextPage(channelID: String) async throws -> ChannelTab<Video> {
        throw URLError(.unsupportedURL)
    }
    func fetchShortsNextPage(channelID: String) async throws -> ChannelTab<Video> {
        throw URLError(.unsupportedURL)
    }
    func fetchDirectsNextPage(channelID: String) async throws -> ChannelTab<Video> {
        throw URLError(.unsupportedURL)
    }
    func fetchPlaylistsNextPage(channelID: String) async throws -> ChannelTab<Playlist> {
        throw URLError(.unsupportedURL)
    }
}
