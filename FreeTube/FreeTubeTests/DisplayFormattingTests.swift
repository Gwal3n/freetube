import XCTest
@testable import FreeTube

@MainActor
final class DisplayFormattingTests: XCTestCase {
    func testExactViewCountReadsOnlyPlainViewText() {
        XCTAssertEqual(PlayerDetailsModel.exactViewCount(in: "5,364,808 views"), 5_364_808)
        XCTAssertEqual(PlayerDetailsModel.exactViewCount(in: "1 view"), 1)
        XCTAssertNil(PlayerDetailsModel.exactViewCount(in: "No views"))
        XCTAssertNil(PlayerDetailsModel.exactViewCount(in: "1.2K watching"))
        XCTAssertNil(PlayerDetailsModel.exactViewCount(in: "12K views"))
    }

    func testCommentLikeCountsKeepCompactMagnitude() {
        XCTAssertEqual(Mappers.parseAbbreviatedCount("73K"), 73_000)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("4.1K"), 4_100)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1.2M"), 1_200_000)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("264"), 264)
        XCTAssertEqual(Video.compactNumber(73_000), "73K")
        XCTAssertEqual(Video.compactNumber(264), "264")
    }

    func testLiveSearchViewerCountsKeepMagnitudeAndWatchingLabel() {
        // "1.2K watching" must not collapse to 12 via digits-only stripping.
        XCTAssertEqual(Mappers.parseAbbreviatedCount("1.2K watching"), 1_200)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("45.3K watching"), 45_300)
        XCTAssertEqual(Mappers.parseAbbreviatedCount("856 watching"), 856)
        let live = Video(
            id: "abcdefghijk",
            title: "Live",
            channelID: "UCtest",
            channelName: "Channel",
            channelThumbnailURL: nil,
            thumbnailURL: nil,
            duration: nil,
            viewCount: 1_200,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: true,
            isShort: false
        )
        XCTAssertEqual(live.viewCountString, "1.2K watching")
        let vod = Video(
            id: live.id,
            title: live.title,
            channelID: live.channelID,
            channelName: live.channelName,
            channelThumbnailURL: nil,
            thumbnailURL: nil,
            duration: 120,
            viewCount: 1_200,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
        XCTAssertEqual(vod.viewCountString, "1.2K views")
    }

    func testDisplayWhitespaceCollapsesRunsAndKeepsCleanTitles() {
        XCTAssertEqual("Alive 2007  [Full Concert]".collapsingDisplayWhitespace, "Alive 2007 [Full Concert]")
        XCTAssertEqual("Line\nbreak\ttab".collapsingDisplayWhitespace, "Line break tab")
        XCTAssertEqual("Already clean".collapsingDisplayWhitespace, "Already clean")
    }
}
