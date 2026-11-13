import Foundation
import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
final class FeedVideoFilterTests: XCTestCase {
    func testLoadPrefersSavedJSONOverLegacyKeys() throws {
        let defaults = UserDefaults(suiteName: "FeedVideoFilterTests.json")!
        defer { defaults.removePersistentDomain(forName: "FeedVideoFilterTests.json") }

        var saved = FeedVideoFilter()
        saved.watch = .hideWatched
        saved.uploaded = .pastMonth
        saved.length = .overTwentyMinutes
        saved.views = .overMillion
        try defaults.set(JSONEncoder().encode(saved), forKey: "feedVideoFilter")
        defaults.set("unwatchedOnly", forKey: "feedWatchFilter")
        defaults.set("underFourMinutes", forKey: "feedDurationFilter")

        XCTAssertEqual(FeedVideoFilter.load(defaults), saved)
    }

    func testLoadMigratesLegacyWatchAndDurationKeys() {
        let defaults = UserDefaults(suiteName: "FeedVideoFilterTests.legacy")!
        defer { defaults.removePersistentDomain(forName: "FeedVideoFilterTests.legacy") }

        defaults.set(FeedWatchFilter.onlyFinished.rawValue, forKey: "feedWatchFilter")
        defaults.set(SearchVideoFilters.Length.fourToTwentyMinutes.rawValue, forKey: "feedDurationFilter")

        let filter = FeedVideoFilter.load(defaults)
        XCTAssertEqual(filter.watch, .onlyFinished)
        XCTAssertEqual(filter.length, .fourToTwentyMinutes)
        XCTAssertEqual(filter.uploaded, .anytime)
        XCTAssertEqual(filter.views, .any)
    }

    func testLoadMigratesCustomDurationMinutesToSeconds() {
        let defaults = UserDefaults(suiteName: "FeedVideoFilterTests.custom")!
        defer { defaults.removePersistentDomain(forName: "FeedVideoFilterTests.custom") }

        defaults.set(SearchVideoFilters.Length.custom.rawValue, forKey: "feedDurationFilter")
        defaults.set(5, forKey: "feedCustomDurationMinimumMinutes")
        defaults.set(20, forKey: "feedCustomDurationMaximumMinutes")

        let filter = FeedVideoFilter.load(defaults)
        XCTAssertEqual(filter.length, .custom)
        XCTAssertEqual(filter.customLengthRange, .init(minimum: 300, maximum: 1_200))
    }

    func testIncludesCombinesWatchAndSharedMetadataPresets() {
        var filter = FeedVideoFilter()
        filter.watch = .onlyFinished
        filter.uploaded = .pastWeek
        filter.length = .fourToTwentyMinutes
        filter.views = .tenToHundredThousand
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let video = Video(
            id: "video", title: "Video", channelID: "channel", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil,
            duration: 600, viewCount: 42_000, publishedAt: nil,
            publishedRelative: "2 days ago", descriptionSnippet: nil,
            isLive: false, isShort: false
        )

        XCTAssertTrue(filter.includes(video, status: .finished, now: now))
        XCTAssertFalse(filter.includes(video, status: .partial, now: now))
        XCTAssertFalse(filter.includes(
            Video(
                id: "old", title: "Old", channelID: "channel", channelName: "Channel",
                channelThumbnailURL: nil, thumbnailURL: nil,
                duration: 600, viewCount: 42_000, publishedAt: nil,
                publishedRelative: "2 months ago", descriptionSnippet: nil,
                isLive: false, isShort: false
            ),
            status: .finished,
            now: now
        ))
    }

    func testSaveRoundTripsThroughUserDefaults() throws {
        let defaults = UserDefaults(suiteName: "FeedVideoFilterTests.roundTrip")!
        defer { defaults.removePersistentDomain(forName: "FeedVideoFilterTests.roundTrip") }

        var filter = FeedVideoFilter()
        filter.watch = .hideWatched
        filter.uploaded = .custom
        filter.customUploadedRange = .init(
            firstDay: Date(timeIntervalSince1970: 1_700_000_000),
            lastDay: Date(timeIntervalSince1970: 1_700_086_400)
        )
        filter.length = .custom
        filter.customLengthRange = .init(minimum: 60, maximum: nil)
        filter.views = .custom
        filter.customViewsRange = .init(minimum: 1_000, maximum: 50_000)
        filter.save(defaults)

        XCTAssertEqual(FeedVideoFilter.load(defaults), filter)
    }
}
