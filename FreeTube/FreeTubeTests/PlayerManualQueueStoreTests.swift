import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class PlayerManualQueueStoreTests: XCTestCase {
    func testPlayNextReplacesDuplicateAndUndoRestoresPosition() {
        let a = video("a")
        let b = video("b")
        let c = video("c")

        let next = PlayerManualQueueStore.insertingNext(c, into: [a, b, c])
        XCTAssertEqual(next.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(PlayerManualQueueStore.appending(b, to: next).map(\.id), ["c", "a", "b"])

        let removed = PlayerManualQueueStore.removing("a", from: next)
        XCTAssertEqual(PlayerManualQueueStore.restoring(a, at: 1, to: removed).map(\.id), ["c", "a", "b"])
        XCTAssertEqual(PlayerManualQueueStore.restoring(a, at: 1, to: next).map(\.id), ["c", "a", "b"])
    }

    func testClearUndoKeepsNewlyAddedItemsWithoutDuplicates() {
        let original = [video("a"), video("b")]
        let addedAfterClear = [video("b"), video("c")]

        XCTAssertEqual(
            PlayerManualQueueStore.restoring(original, to: addedAfterClear).map(\.id),
            ["a", "b", "c"]
        )
    }

    func testReorderingVisibleItemsPreservesBlockedSlots() {
        let items = [video("a"), video("blocked"), video("b"), video("c")]
        let reordered = PlayerManualQueueStore.reordered(
            items,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3,
            isBlocked: { $0.id == "blocked" }
        )
        XCTAssertEqual(reordered?.map(\.id), ["b", "blocked", "c", "a"])
        XCTAssertNil(PlayerManualQueueStore.reordered(items, fromOffsets: IndexSet(integer: 4), toOffset: 0, isBlocked: { _ in false }))
    }

    func testPersistAndRestoreUseExistingStorageFormat() throws {
        let suite = "PlayerManualQueueStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = [video("a"), video("b")]

        PlayerManualQueueStore.persist(original, to: defaults)
        XCTAssertEqual(PlayerManualQueueStore.restore(from: defaults).map(\.id), ["a", "b"])
        XCTAssertNotNil(defaults.string(forKey: "manualQueue"))
    }

    private func video(_ id: String) -> Video {
        Video(
            id: id, title: "Video", channelID: "channel", channelName: "Channel",
            channelThumbnailURL: nil, thumbnailURL: nil, duration: 60,
            viewCount: nil, publishedAt: nil, descriptionSnippet: nil,
            isLive: false, isShort: false
        )
    }
}
