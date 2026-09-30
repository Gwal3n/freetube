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

    func testHistorySnapshotDecodesOldBackupWithoutChannelID() throws {
        let legacyJSON = """
        {"videoID":"video","title":"Video","channelName":"Channel",\
        "watchedAt":0,"lastPosition":60,"duration":240}
        """
        let restored = try JSONDecoder().decode(WatchHistorySnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(restored.channelID)
    }

    func testHistorySnapshotRetainsChannelIDInBackup() throws {
        let original = WatchHistorySnapshot(
            videoID: "video",
            title: "Video",
            channelName: "Channel",
            channelID: "UC123",
            thumbnailURL: nil,
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastPosition: 60,
            duration: 240
        )
        let restored = try JSONDecoder().decode(WatchHistorySnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.channelID, "UC123")
    }

    private func snapshot(position: TimeInterval, duration: TimeInterval) -> WatchHistorySnapshot {
        WatchHistorySnapshot(
            videoID: "video",
            title: "Video",
            channelName: "Channel",
            channelID: nil,
            thumbnailURL: nil,
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastPosition: position,
            duration: duration
        )
    }
}
