import XCTest
@testable import FreeTube

final class ChannelVideoSortTests: XCTestCase {
    func testPopularFallbackOrdersByViewCount() {
        let videos = [video("low", views: 10), video("high", views: 1_000), video("mid", views: 100)]

        XCTAssertEqual(ChannelVideoSort.popular.localFallback(videos).map(\.id), ["high", "mid", "low"])
    }

    func testOldestFallbackReversesServerOrder() {
        let videos = [video("newest", views: 1), video("middle", views: 2), video("oldest", views: 3)]

        XCTAssertEqual(ChannelVideoSort.oldest.localFallback(videos).map(\.id), ["oldest", "middle", "newest"])
    }

    func testSortsMapToStableFilterChipPositions() {
        XCTAssertEqual(ChannelVideoSort.allCases.map(\.chipIndex), [0, 1, 2])
        XCTAssertEqual(Set(ChannelVideoSort.allCases.map(\.requestParameters)).count, 1)
    }

    private func video(_ id: String, views: Int) -> Video {
        Video(
            id: id,
            title: id,
            channelID: "channel",
            channelName: "Channel",
            channelThumbnailURL: nil,
            thumbnailURL: nil,
            duration: nil,
            viewCount: views,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }
}
