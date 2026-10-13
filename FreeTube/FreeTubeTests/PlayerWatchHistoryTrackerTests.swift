import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class PlayerWatchHistoryTrackerTests: XCTestCase {
    func testSeekingDoesNotQualifyPlaybackHistory() {
        let tracker = PlayerWatchHistoryTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: true, now: start)
        XCTAssertFalse(tracker.hasQualifiedForHistory(duration: 100))
        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: true, now: start.addingTimeInterval(5))
        // A delayed observer callback counts at most one observed second.
        XCTAssertFalse(tracker.hasQualifiedForHistory(duration: 100))
        for second in 6...9 {
            tracker.accumulatePlaybackTime(
                isPlaying: true,
                recordsHistory: true,
                now: start.addingTimeInterval(TimeInterval(second))
            )
        }
        XCTAssertTrue(tracker.hasQualifiedForHistory(duration: 100))
    }

    func testPauseAndDisabledHistoryDoNotAccumulateTime() {
        let tracker = PlayerWatchHistoryTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: true, now: start)
        tracker.accumulatePlaybackTime(isPlaying: false, recordsHistory: true, now: start.addingTimeInterval(1))
        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: true, now: start.addingTimeInterval(10))
        XCTAssertFalse(tracker.hasQualifiedForHistory(duration: 20))
        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: true, now: start.addingTimeInterval(11))
        XCTAssertTrue(tracker.hasQualifiedForHistory(duration: 20))
        tracker.accumulatePlaybackTime(isPlaying: true, recordsHistory: false, now: start.addingTimeInterval(12))
        XCTAssertFalse(tracker.hasQualifiedForHistory(duration: 20))
    }

    func testResumeRejectsShortAndNearlyFinishedPositions() {
        let tracker = PlayerWatchHistoryTracker()
        XCTAssertNil(tracker.resumePosition((9, 240), for: "video", currentVideoID: "video", duration: 240, recordsProgress: true))
        XCTAssertNil(tracker.resumePosition((220, 240), for: "video", currentVideoID: "video", duration: 240, recordsProgress: true))
        XCTAssertNil(tracker.resumePosition((60, 240), for: "video", currentVideoID: "other", duration: 240, recordsProgress: true))
        XCTAssertNil(tracker.resumePosition((60, 240), for: "video", currentVideoID: "video", duration: 240, recordsProgress: false))
        XCTAssertEqual(tracker.resumePosition((60, 240), for: "video", currentVideoID: "video", duration: 240, recordsProgress: true), 60)
    }
}
