import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class TemporaryYouTubePlaylistShareTests: XCTestCase {
    func testBuildsOrderedAnonymousPlaylistLink() {
        guard let share = TemporaryYouTubePlaylistShare.make(videoIDs: ["jfKfPfyJRdk", "5qap5aO4i9A"]) else {
            return XCTFail("Expected a valid temporary playlist link")
        }

        XCTAssertEqual(share.url.scheme, "https")
        XCTAssertEqual(share.url.host, "www.youtube.com")
        XCTAssertEqual(share.url.path, "/watch_videos")
        XCTAssertEqual(URLComponents(url: share.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "video_ids" })?.value, "jfKfPfyJRdk,5qap5aO4i9A")
        XCTAssertEqual(share.includedCount, 2)
    }

    func testLargeListIsExplicitlyCapped() {
        let ids = (0..<52).map { String(format: "video%06d", $0) }
        guard let share = TemporaryYouTubePlaylistShare.make(videoIDs: ids) else {
            return XCTFail("Expected a valid temporary playlist link")
        }

        XCTAssertEqual(share.availableCount, 52)
        XCTAssertEqual(share.includedCount, 50)
        XCTAssertEqual(URLComponents(url: share.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "video_ids" })?.value,
            ids.prefix(50).joined(separator: ","))
        XCTAssertNil(TemporaryYouTubePlaylistShare.make(videoIDs: []))
        XCTAssertNil(TemporaryYouTubePlaylistShare.make(videoIDs: ["not a video ID"]))
        XCTAssertNil(TemporaryYouTubePlaylistShare.make(videoIDs: ["jfKfPfyJRdk", "not a video ID"]))
    }
}
