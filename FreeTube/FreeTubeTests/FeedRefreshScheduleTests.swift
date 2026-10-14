import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class FeedRefreshScheduleTests: XCTestCase {
    func testCompletedRefreshWaitsForChosenInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(FeedRefreshSchedule.isDue(
            now: now,
            lastComplete: now.addingTimeInterval(-3_600),
            lastAttempt: now.addingTimeInterval(-3_600),
            interval: .everySixHours
        ))
        XCTAssertTrue(FeedRefreshSchedule.isDue(
            now: now,
            lastComplete: now.addingTimeInterval(-6 * 3_600),
            lastAttempt: now.addingTimeInterval(-6 * 3_600),
            interval: .everySixHours
        ))
    }

    func testPartialRefreshRetriesAfterCooldownNotFullInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(FeedRefreshSchedule.isDue(
            now: now,
            lastComplete: nil,
            lastAttempt: now.addingTimeInterval(-10 * 60),
            interval: .daily
        ))
        XCTAssertTrue(FeedRefreshSchedule.isDue(
            now: now,
            lastComplete: nil,
            lastAttempt: now.addingTimeInterval(-31 * 60),
            interval: .daily
        ))
    }
}
