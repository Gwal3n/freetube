import XCTest
@testable import FreeTube

final class CommentTimestampLinksTests: XCTestCase {
    func testFindsShortAndHourLongTimestamps() {
        let matches = CommentTimestampLinks.matches(in: "Intro 0:12, solo 12:34 and ending 1:02:03")
        XCTAssertEqual(matches.map(\.seconds), [12, 754, 3723])
    }

    func testRejectsPartialAndMalformedTimes() {
        let matches = CommentTimestampLinks.matches(in: "123:45 1:99:30 1:23:456")
        XCTAssertTrue(matches.isEmpty)
    }

    func testRangesReferToTheOriginalCommentText() {
        let text = "Start at 2:15 please"
        let match = try? XCTUnwrap(CommentTimestampLinks.matches(in: text).first)
        guard let match, let range = Range(match.range, in: text) else {
            XCTFail("Expected a timestamp range")
            return
        }
        XCTAssertEqual(String(text[range]), "2:15")
    }
}
