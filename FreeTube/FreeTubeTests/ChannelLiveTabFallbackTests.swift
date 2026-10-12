import XCTest
@testable import FreeTube

final class ChannelLiveTabFallbackTests: XCTestCase {
    func testStreamsTabDecodesLockupVideo() {
        let result = ChannelVideosFallbackService.decodeVideosTab(
            root: response(tabPath: "streams", video: lockupVideo()),
            channelID: "UC_test",
            tabPath: "streams"
        )

        XCTAssertEqual(result.videos.map(\.id), ["live-video"])
        XCTAssertEqual(result.videos.first?.title, "Live video")
    }

    func testSelectedHomeTabIsNotMistakenForLive() {
        let result = ChannelVideosFallbackService.decodeVideosTab(
            root: response(tabPath: "featured", video: lockupVideo()),
            channelID: "UC_test",
            tabPath: "streams"
        )

        XCTAssertTrue(result.videos.isEmpty)
    }

    private func response(tabPath: String, video: [String: Any]) -> [String: Any] {
        [
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "selected": true,
                            "endpoint": ["commandMetadata": ["webCommandMetadata": ["url": "/@test/\(tabPath)"]]],
                            "content": ["richGridRenderer": ["contents": [
                                ["richItemRenderer": ["content": ["lockupViewModel": video]]]
                            ]]]
                        ]
                    ]]
                ]
            ]
        ]
    }

    private func lockupVideo() -> [String: Any] {
        [
            "contentId": "live-video",
            "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
            "metadata": ["lockupMetadataViewModel": ["title": ["content": "Live video"]]]
        ]
    }
}
