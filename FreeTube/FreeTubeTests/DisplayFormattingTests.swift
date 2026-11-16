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

    func testDisplayWhitespaceCollapsesRunsAndKeepsCleanTitles() {
        XCTAssertEqual("Alive 2007  [Full Concert]".collapsingDisplayWhitespace, "Alive 2007 [Full Concert]")
        XCTAssertEqual("Line\nbreak\ttab".collapsingDisplayWhitespace, "Line break tab")
        XCTAssertEqual("Already clean".collapsingDisplayWhitespace, "Already clean")
    }
}
