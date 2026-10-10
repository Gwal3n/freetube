import Foundation
import XCTest

@testable import FreeTube

@MainActor
final class SavedMomentStoreTests: XCTestCase {
    func testMomentPersistsIndependentlyOfHistoryAndDeduplicatesNearbyTaps() throws {
        let suiteName = "com.leshko.freetube.tests.savedMoments.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SavedMomentStore(defaults: defaults)
        let video = testVideo()

        let first = try XCTUnwrap(store.add(video: video, time: 42.5))
        let duplicate = try XCTUnwrap(store.add(video: video, time: 42.8))
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(store.moments.count, 1)

        store.rename(id: first.id, label: "  Good   part  ")
        let restored = SavedMomentStore(defaults: defaults)
        XCTAssertEqual(restored.moments.first?.label, "Good part")
        XCTAssertEqual(restored.moments.first?.time, 42.5)
        XCTAssertEqual(restored.moments.first?.timestampText, "0:42")
    }

    func testFullBackupCanCarryMomentsWithoutBreakingOlderBackups() throws {
        var backup = AppBackup(
            formatVersion: 1,
            exportedAt: .now,
            settings: [:],
            subscriptions: [],
            playlists: [],
            watchHistory: [],
            searchHistory: [],
            favoriteVideos: [],
            favoritePlaylists: []
        )
        let oldData = try JSONEncoder().encode(backup)
        XCTAssertNil(try JSONDecoder().decode(AppBackup.self, from: oldData).savedMoments)

        backup.savedMoments = [SavedMoment(
            id: UUID(), video: testVideo(), time: 42, label: "Moment", savedAt: .now
        )]
        let restored = try JSONDecoder().decode(AppBackup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(restored.savedMoments?.first?.label, "Moment")
    }

    func testVideoMomentsAreFilteredAndOrderedByPlaybackTime() throws {
        let suiteName = "com.leshko.freetube.tests.savedMoments.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SavedMomentStore(defaults: defaults)

        store.add(video: testVideo(), time: 80)
        store.add(video: testVideo(id: "9bZkp7q19f0"), time: 10)
        store.add(video: testVideo(), time: 20)

        XCTAssertEqual(store.moments(for: "dQw4w9WgXcQ").map(\.time), [20, 80])
        XCTAssertEqual(store.moments(for: "9bZkp7q19f0").map(\.time), [10])
        XCTAssertTrue(store.hasMoments(for: "dQw4w9WgXcQ"))
        XCTAssertFalse(store.hasMoments(for: "unwatchedID"))
    }

    private func testVideo(id: String = "dQw4w9WgXcQ") -> Video {
        Video(
            id: id,
            title: "Test video",
            channelID: "channel",
            channelName: "Test channel",
            channelThumbnailURL: nil,
            thumbnailURL: nil,
            duration: 120,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }
}
