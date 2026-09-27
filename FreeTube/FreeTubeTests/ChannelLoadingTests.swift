import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class ChannelLoadingTests: XCTestCase {
    func testCancelledAppearanceAndReopeningShareTheRequest() async {
        let service = ChannelLoadingFixture()
        service.allowSuccess()
        service.holdRequests = true
        let model = ChannelViewModel(channelID: "test-channel", service: service)
        let appearance = Task { await model.load() }
        await service.waitForRequest()
        appearance.cancel()

        // The queued completion runs when the reopened caller yields to the shared request.
        // No real networking, arbitrary delays, or reliance on a cancelled URLSession task.
        let completion = Task { service.completeRequest() }
        await model.load()
        await completion.value
        await appearance.value

        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(model.details?.channel.id, "test-channel")
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.initialLoadFailed)
        XCTAssertNil(model.errorState)
    }

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
        service.allowSuccess()
        await model.load()
        XCTAssertEqual(model.details?.channel.id, "test-channel")
        XCTAssertFalse(model.isLoading)
    }
}

@MainActor
private final class ChannelLoadingFixture: ChannelServicing {
    var holdRequests = false
    private(set) var requestCount = 0
    private var pendingRequest: CheckedContinuation<Void, Never>?
    private var requestStarted: CheckedContinuation<Void, Never>?
    private var succeeds = false
    private var cancels = false

    func allowSuccess() {
        succeeds = true
        cancels = false
    }
    func cancelRequests() { cancels = true }

    func waitForRequest() async {
        if pendingRequest != nil { return }
        await withCheckedContinuation { requestStarted = $0 }
    }

    func completeRequest() {
        pendingRequest?.resume()
        pendingRequest = nil
    }

    func fetchChannel(id: String) async throws -> ChannelDetails {
        requestCount += 1
        if holdRequests {
            await withCheckedContinuation { continuation in
                pendingRequest = continuation
                requestStarted?.resume()
                requestStarted = nil
            }
        }
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
