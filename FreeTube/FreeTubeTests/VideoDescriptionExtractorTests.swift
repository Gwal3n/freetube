import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class VideoDescriptionExtractorTests: XCTestCase {
    func testLinksAfterEmojiUseUTF16OffsetsAndKeepTrailingText() throws {
        let text = "Intro 👕 https://example.com and ChessMood playlist. Tail 🎬"
        let source = text as NSString
        let websiteRange = source.range(of: "https://example.com")
        let playlistRange = source.range(of: "ChessMood playlist")
        let redirect = "https://www.youtube.com/redirect?q=https%3A%2F%2Fexample.com%2F"
        let runs: [[String: Any]] = [
            [
                "startIndex": websiteRange.location,
                "length": websiteRange.length,
                "onTap": ["innertubeCommand": ["urlEndpoint": ["url": redirect]]]
            ],
            [
                "startIndex": playlistRange.location,
                "length": playlistRange.length,
                "onTap": ["innertubeCommand": ["browseEndpoint": ["browseId": "VLPL123"]]]
            ]
        ]
        let response: [String: Any] = [
            "contents": [
                "twoColumnWatchNextResults": [
                    "results": [
                        "results": [
                            "contents": [[
                                "videoSecondaryInfoRenderer": [
                                    "attributedDescription": ["content": text, "commandRuns": runs]
                                ]
                            ]]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: response)
        let extracted = try XCTUnwrap(VideoDescriptionExtractor.extract(from: data))

        XCTAssertEqual(extracted.text, text)
        XCTAssertEqual(extracted.parts.map(\.text).joined(), text)
        XCTAssertTrue(extracted.parts.last?.text.contains("Tail 🎬") == true)
        let website = try XCTUnwrap(extracted.parts.first { $0.text == "https://example.com" })
        XCTAssertEqual(
            website.action,
            VideoDescriptionPart.Action.externalURL(try XCTUnwrap(URL(string: "https://example.com/")))
        )
        XCTAssertTrue(extracted.parts.contains {
            $0.text == "ChessMood playlist" && $0.action == .playlist("VLPL123")
        })
    }
}
