import XCTest
import YouTubeKit
@testable import FreeTube

final class MembersOnlyFilteringTests: XCTestCase {
    func testExplicitMembersOnlyFlagIsDropped() {
        let video = YTVideo(videoId: "abcdefghijk", title: "Secret", memberOnly: true)
        XCTAssertTrue(Mappers.isMembersOnlyListing(video))
        XCTAssertNil(Mappers.video(from: video))
    }

    func testPublicVideoStillMaps() {
        let video = YTVideo(
            videoId: "abcdefghijk",
            title: "Public",
            viewCount: "12K views",
            timePosted: "3 days ago",
            timeLength: "12:34",
            memberOnly: false
        )
        let mapped = Mappers.video(from: video)
        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.viewCount, 12_000)
        XCTAssertEqual(mapped?.publishedRelative, "3 days ago")
    }

    func testLockupDateParkedInViewCountIsTreatedAsMembersOnly() {
        // Channel lockups omit memberOnly; YouTubeKit parks the lone date part in viewCount.
        let video = YTVideo(
            videoId: "abcdefghijk",
            title: "Members drop",
            viewCount: "1 day ago",
            timePosted: "1 day ago",
            timeLength: "10:00"
        )
        XCTAssertTrue(Mappers.isMembersOnlyListing(video))
        XCTAssertNil(Mappers.video(from: video))
    }

    func testRelativeAgeDetection() {
        XCTAssertTrue(Mappers.looksLikeRelativeAge("1 day ago"))
        XCTAssertTrue(Mappers.looksLikeRelativeAge("Streamed 3 hours ago"))
        XCTAssertFalse(Mappers.looksLikeRelativeAge("1 view"))
        XCTAssertFalse(Mappers.looksLikeRelativeAge("12K views"))
        XCTAssertFalse(Mappers.looksLikeRelativeAge("856"))
    }
}
