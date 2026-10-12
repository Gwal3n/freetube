import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class VideoInfosWithRawDurationResponseTests: XCTestCase {
    func testExtractsDurationFromPlayerResponseWithoutAnotherRequest() {
        let html = Data("""
        <script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"548"}};</script><div id="player">
        """.utf8)

        XCTAssertEqual(VideoInfosWithRawDurationResponse.duration(from: html), 548)
    }

    func testAcceptsNumericDurationAndRejectsMissingOrZeroDuration() {
        let numeric = Data("""
        <script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":123}};</script><div id="player">
        """.utf8)
        let zero = Data("""
        <script>var ytInitialPlayerResponse = {"videoDetails":{"lengthSeconds":"0"}};</script><div id="player">
        """.utf8)
        let missing = Data("""
        <script>var ytInitialPlayerResponse = {"videoDetails":{}};</script><div id="player">
        """.utf8)

        XCTAssertEqual(VideoInfosWithRawDurationResponse.duration(from: numeric), 123)
        XCTAssertNil(VideoInfosWithRawDurationResponse.duration(from: zero))
        XCTAssertNil(VideoInfosWithRawDurationResponse.duration(from: missing))
    }
}
