import XCTest
@testable import FreeTube

final class WatchHistoryTests: XCTestCase {
    func testEligibleHistoryEntryProducesResumeProgress() throws {
        let entry = snapshot(position: 60, duration: 240)

        XCTAssertEqual(try XCTUnwrap(entry.resumableProgress), 0.25, accuracy: 0.001)
    }

    func testShortProgressDoesNotResume() {
        XCTAssertNil(snapshot(position: 9, duration: 240).resumableProgress)
    }

    func testNearlyFinishedVideoDoesNotResume() {
        XCTAssertNil(snapshot(position: 195, duration: 200).resumableProgress)
    }

    private func snapshot(position: TimeInterval, duration: TimeInterval) -> WatchHistorySnapshot {
        WatchHistorySnapshot(
            videoID: "video",
            title: "Video",
            channelName: "Channel",
            thumbnailURL: nil,
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastPosition: position,
            duration: duration
        )
    }
}
