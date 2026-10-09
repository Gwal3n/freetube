import Foundation
import XCTest
@testable import FreeTube

final class SearchVideoFiltersTests: XCTestCase {
    func testWatchStatusFilterDoesNotDependOnProgressBarVisibility() {
        var filters = SearchVideoFilters()
        let video = makeVideo()

        filters.watch = .hideWatched
        XCTAssertTrue(filters.includes(video, status: nil, now: .now))
        XCTAssertFalse(filters.includes(video, status: .partial, now: .now))

        filters.watch = .onlyFinished
        XCTAssertFalse(filters.includes(video, status: .partial, now: .now))
        XCTAssertTrue(filters.includes(video, status: .finished, now: .now))
    }

    func testUploadAgeUsesApproximateRelativeMetadata() {
        var filters = SearchVideoFilters()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let video = makeVideo(publishedRelative: "2 weeks ago")

        filters.uploaded = .pastWeek
        XCTAssertFalse(filters.includes(video, status: nil, now: now))
        filters.uploaded = .pastMonth
        XCTAssertTrue(filters.includes(video, status: nil, now: now))
        XCTAssertFalse(filters.includes(makeVideo(publishedRelative: nil), status: nil, now: now))
    }

    func testLengthAndViewRangesExcludeUnknownMetadata() {
        var filters = SearchVideoFilters()
        filters.length = .fourToTwentyMinutes
        filters.views = .tenToHundredThousand

        XCTAssertTrue(filters.includes(makeVideo(duration: 600, views: 42_000), status: nil, now: .now))
        XCTAssertFalse(filters.includes(makeVideo(duration: nil, views: 42_000), status: nil, now: .now))
        XCTAssertFalse(filters.includes(makeVideo(duration: 600, views: nil), status: nil, now: .now))
    }

    private func makeVideo(
        duration: TimeInterval? = 600,
        views: Int? = 42_000,
        publishedRelative: String? = "2 weeks ago"
    ) -> Video {
        Video(
            id: "video", title: "Video", channelID: "channel", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil,
            duration: duration, viewCount: views, publishedAt: nil,
            publishedRelative: publishedRelative, descriptionSnippet: nil,
            isLive: false, isShort: false
        )
    }
}
