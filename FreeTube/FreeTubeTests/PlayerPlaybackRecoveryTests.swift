import XCTest
@testable import FreeTube

final class PlayerPlaybackRecoveryTests: XCTestCase {
    func testVODRecoveryKeepsPositionAndFailedStrategy() {
        let recovery = PlayerPlaybackRecovery(
            sessionID: 7,
            failedStrategy: .native,
            currentTime: .nan,
            elapsed: 42,
            liveSeekableRange: nil,
            isLive: false,
            resumeFromHistoryIfUnstarted: true
        )

        XCTAssertEqual(recovery.sessionID, 7)
        XCTAssertEqual(recovery.failedStrategy, .native)
        XCTAssertEqual(recovery.position, 42)
        XCTAssertFalse(recovery.resumeFromHistoryIfUnstarted)
    }

    func testUnstartedVODCanResumeFromStoredHistory() {
        let recovery = PlayerPlaybackRecovery(
            sessionID: 1,
            failedStrategy: nil,
            currentTime: 0,
            elapsed: 0,
            liveSeekableRange: nil,
            isLive: false,
            resumeFromHistoryIfUnstarted: true
        )

        XCTAssertTrue(recovery.resumeFromHistoryIfUnstarted)
    }

    func testLiveRecoveryPreservesDistanceBehindNewestContiguousWindow() {
        let recovery = PlayerPlaybackRecovery(
            sessionID: 1,
            failedStrategy: .native,
            currentTime: 120,
            elapsed: 110,
            liveSeekableRange: 100...160,
            isLive: true,
            resumeFromHistoryIfUnstarted: true
        )

        XCTAssertEqual(recovery.position, 40)
        XCTAssertFalse(recovery.resumeFromHistoryIfUnstarted)
        XCTAssertEqual(recovery.liveSeekTarget(in: [0...50, 110...160]), 120)
        XCTAssertNil(recovery.liveSeekTarget(in: []))
    }

    func testNearLiveEdgeUsesLiveSeekInsteadOfAnAbsoluteTarget() {
        let recovery = PlayerPlaybackRecovery(
            sessionID: 1,
            failedStrategy: nil,
            currentTime: 158,
            elapsed: 158,
            liveSeekableRange: 100...160,
            isLive: true,
            resumeFromHistoryIfUnstarted: false
        )

        XCTAssertEqual(recovery.position, 2)
        XCTAssertNil(recovery.liveSeekTarget(in: [100...160]))
    }
}
