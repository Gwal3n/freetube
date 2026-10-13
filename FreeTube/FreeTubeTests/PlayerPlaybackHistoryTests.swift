import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class PlayerPlaybackHistoryTests: XCTestCase {
    func testPreviousThenNextReturnsToTheSameVideo() {
        var history = PlayerPlaybackHistory()
        history.record(entry("a"))
        history.record(entry("b"))
        history.record(entry("c"))

        XCTAssertEqual(history.moveBackward(where: { _ in true })?.video.id, "b")
        XCTAssertEqual(history.moveForward(where: { _ in true })?.video.id, "c")
        XCTAssertEqual(history.currentIndex, 2)
    }

    func testNewSelectionReplacesTheForwardBranch() {
        var history = PlayerPlaybackHistory()
        history.record(entry("a"))
        history.record(entry("b"))
        history.record(entry("c"))
        _ = history.moveBackward(where: { _ in true })
        history.record(entry("d"))

        XCTAssertEqual(history.count, 3)
        XCTAssertFalse(history.hasForwardEntry)
        XCTAssertEqual(history.moveBackward(where: { _ in true })?.video.id, "b")
        XCTAssertEqual(history.moveForward(where: { _ in true })?.video.id, "d")
    }

    func testBlockedEntriesAreSkippedWithoutMovingOnFailure() {
        var history = PlayerPlaybackHistory()
        history.record(entry("a"))
        history.record(entry("b"))
        history.record(entry("c"))

        XCTAssertEqual(history.moveBackward(where: { $0.id != "b" })?.video.id, "a")
        XCTAssertEqual(history.moveForward(where: { $0.id != "b" })?.video.id, "c")
        XCTAssertNil(history.moveBackward(where: { _ in false }))
        XCTAssertEqual(history.currentIndex, 2)
    }

    func testHistoryIsBoundedAndPreservesPlaybackContext() {
        var history = PlayerPlaybackHistory()
        for number in 0..<55 {
            history.record(entry(String(number), skipRecommendations: true))
        }
        XCTAssertEqual(history.count, 50)
        XCTAssertEqual(history.currentIndex, 49)

        for _ in 0..<49 { _ = history.moveBackward(where: { _ in true }) }
        XCTAssertEqual(history.currentIndex, 0)
        XCTAssertNil(history.moveBackward(where: { _ in true }))
        XCTAssertEqual(history.moveForward(where: { _ in true })?.video.id, "6")
        history.replaceCurrent(entry("playlist", skipRecommendations: true, preservesPlaylistPosition: true))
        XCTAssertTrue(history.moveBackward(where: { _ in true })?.skipRecommendations == true)
        XCTAssertTrue(history.moveForward(where: { _ in true })?.preservesPlaylistPosition == true)
    }

    func testMetadataRefreshDoesNotCreateAnotherHistoryEntry() {
        var history = PlayerPlaybackHistory()
        history.record(entry("a", skipRecommendations: true))
        history.record(entry("a"))
        XCTAssertEqual(history.count, 1)

        let enriched = video("a", title: "Updated title")
        history.updateCurrentVideo(enriched)
        history.record(entry("b"))
        XCTAssertEqual(history.moveBackward(where: { _ in true })?.video.title, "Updated title")
        XCTAssertTrue(history.moveForward(where: { _ in true })?.skipRecommendations == false)
    }

    private func entry(
        _ id: String,
        skipRecommendations: Bool = false,
        preservesPlaylistPosition: Bool = false
    ) -> PlayerPlaybackHistory.Entry {
        .init(
            video: video(id),
            skipRecommendations: skipRecommendations,
            preservesPlaylistPosition: preservesPlaylistPosition
        )
    }

    private func video(_ id: String, title: String = "Video") -> Video {
        Video(
            id: id, title: title, channelID: "channel", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil, duration: 60,
            viewCount: nil, publishedAt: nil, descriptionSnippet: nil,
            isLive: false, isShort: false
        )
    }
}
