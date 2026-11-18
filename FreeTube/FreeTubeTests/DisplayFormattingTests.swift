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

    func testDisplayWhitespaceCollapsesRunsAndKeepsCleanTitles() {
        XCTAssertEqual("Alive 2007  [Full Concert]".collapsingDisplayWhitespace, "Alive 2007 [Full Concert]")
        XCTAssertEqual("Line\nbreak\ttab".collapsingDisplayWhitespace, "Line break tab")
        XCTAssertEqual("Already clean".collapsingDisplayWhitespace, "Already clean")
    }
}
