import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class LiveViewerCountExtractorTests: XCTestCase {
    func testReadsExplicitLiveSimpleText() throws {
        let data = try watchResponse(isLive: true, label: ["simpleText": "12,345 watching"])
        XCTAssertEqual(LiveViewerCountExtractor.extract(from: data), "12,345 watching")
    }

    func testReadsExplicitLiveRunsWhenSimpleTextIsEmpty() throws {
        let data = try watchResponse(
            isLive: true,
            label: ["simpleText": "", "runs": [["text": "1,234"], ["text": " watching"]]]
        )
        XCTAssertEqual(LiveViewerCountExtractor.extract(from: data), "1,234 watching")
    }

    func testDoesNotConfuseTotalViewsWithLiveViewers() throws {
        let ordinary = try watchResponse(isLive: false, label: ["simpleText": "1,234 views"])
        let unmarked = try watchResponse(isLive: nil, label: ["simpleText": "1,234 watching"])

        XCTAssertNil(LiveViewerCountExtractor.extract(from: ordinary))
        XCTAssertNil(LiveViewerCountExtractor.extract(from: unmarked))
    }

    func testLiveStatsDoNotFallBackToStoredTotalViews() {
        let video = Video(
            id: "abc12345678", title: "Live", channelID: "UC123", channelName: "Creator",
            channelThumbnailURL: nil, thumbnailURL: nil, duration: nil, viewCount: 1_234_567,
            publishedAt: nil, descriptionSnippet: nil, isLive: true, isShort: false
        )

        XCTAssertFalse(PlayerDetailsModel().statsText(for: video).contains("views"))
    }

    private func watchResponse(isLive: Bool?, label: [String: Any]) throws -> Data {
        var renderer: [String: Any] = ["viewCount": label]
        if let isLive { renderer["isLive"] = isLive }
        let response: [String: Any] = [
            "contents": [
                "twoColumnWatchNextResults": [
                    "results": [
                        "results": [
                            "contents": [[
                                "videoPrimaryInfoRenderer": [
                                    "viewCount": ["videoViewCountRenderer": renderer]
                                ]
                            ]]
                        ]
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: response)
    }
}
