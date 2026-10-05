import Foundation
import XCTest
@testable import FreeTube

final class SubscriptionFeedOrderingTests: XCTestCase {
    func testInterleavesOnlyNearTies() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let feed = [
            snapshot("a1", channel: "a", date: now),
            snapshot("a2", channel: "a", date: now.addingTimeInterval(-60)),
            snapshot("a3", channel: "a", date: now.addingTimeInterval(-120)),
            snapshot("b1", channel: "b", date: now.addingTimeInterval(-180)),
            snapshot("b2", channel: "b", date: now.addingTimeInterval(-240))
        ]

        XCTAssertEqual(
            SubscriptionFeedOrdering.diversified(feed, pageSize: 100).map(\.video.id),
            ["a1", "b1", "a2", "b2", "a3"]
        )
    }

    func testDoesNotPromoteAnOldUpload() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let feed = [
            snapshot("a1", channel: "a", date: now),
            snapshot("a2", channel: "a", date: now.addingTimeInterval(-60)),
            snapshot("b1", channel: "b", date: now.addingTimeInterval(-86_400))
        ]

        XCTAssertEqual(
            SubscriptionFeedOrdering.diversified(feed, pageSize: 100).map(\.video.id),
            ["a1", "a2", "b1"]
        )
    }

    func testLoadingAnotherPageKeepsTheFirstPageStable() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let feed = [
            snapshot("a1", channel: "a", date: now),
            snapshot("a2", channel: "a", date: now),
            snapshot("b1", channel: "b", date: now),
            snapshot("a3", channel: "a", date: now),
            snapshot("b2", channel: "b", date: now)
        ]

        let firstPage = SubscriptionFeedOrdering.diversified(Array(feed.prefix(3)), pageSize: 3)
        let twoPages = SubscriptionFeedOrdering.diversified(feed, pageSize: 3)
        XCTAssertEqual(Array(twoPages.prefix(3)).map(\.video.id), firstPage.map(\.video.id))
        XCTAssertEqual(Set(twoPages.map(\.video.id)), Set(feed.map(\.video.id)))
    }

    private func snapshot(_ id: String, channel: String, date: Date) -> SubscriptionFeedSnapshot {
        SubscriptionFeedSnapshot(
            video: Video(
                id: id,
                title: id,
                channelID: channel,
                channelName: channel,
                channelThumbnailURL: nil,
                thumbnailURL: nil,
                duration: nil,
                viewCount: nil,
                publishedAt: date,
                descriptionSnippet: nil,
                isLive: false,
                isShort: false
            ),
            sortDate: date
        )
    }
}
