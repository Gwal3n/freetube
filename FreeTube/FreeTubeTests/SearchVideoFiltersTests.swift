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

    func testCustomDurationAndViewRangesAreInclusiveAndOpenEnded() {
        var filters = SearchVideoFilters()
        filters.length = .custom
        filters.customLengthRange = .init(minimum: 5, maximum: 10)
        filters.views = .custom
        filters.customViewsRange = .init(minimum: 1_000, maximum: nil)

        XCTAssertTrue(filters.includes(makeVideo(duration: 300, views: 1_000), status: nil, now: .now))
        XCTAssertTrue(filters.includes(makeVideo(duration: 600, views: 2_000_000), status: nil, now: .now))
        XCTAssertFalse(filters.includes(makeVideo(duration: 299, views: 1_000), status: nil, now: .now))
        XCTAssertFalse(filters.includes(makeVideo(duration: 601, views: 1_000), status: nil, now: .now))
        XCTAssertFalse(filters.includes(makeVideo(duration: 600, views: 999), status: nil, now: .now))
    }

    func testCustomUploadRangeIncludesBothCalendarDays() {
        var filters = SearchVideoFilters()
        let calendar = Calendar.autoupdatingCurrent
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let last = calendar.date(byAdding: .day, value: 2, to: first) ?? first
        filters.uploaded = .custom
        filters.customUploadedRange = .init(firstDay: first, lastDay: last)

        XCTAssertTrue(filters.includes(
            makeVideo(publishedAt: first.addingTimeInterval(30)), status: nil, now: last
        ))
        XCTAssertTrue(filters.includes(
            makeVideo(publishedAt: last.addingTimeInterval(60)), status: nil, now: last
        ))
        XCTAssertFalse(filters.includes(
            makeVideo(publishedAt: first.addingTimeInterval(-60)), status: nil, now: last
        ))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        XCTAssertFalse(filters.includes(
            makeVideo(publishedAt: nextDay), status: nil, now: nextDay
        ))
    }

    private func makeVideo(
        duration: TimeInterval? = 600,
        views: Int? = 42_000,
        publishedAt: Date? = nil,
        publishedRelative: String? = "2 weeks ago"
    ) -> Video {
        Video(
            id: "video", title: "Video", channelID: "channel", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil,
            duration: duration, viewCount: views, publishedAt: publishedAt,
            publishedRelative: publishedRelative, descriptionSnippet: nil,
            isLive: false, isShort: false
        )
    }
}
