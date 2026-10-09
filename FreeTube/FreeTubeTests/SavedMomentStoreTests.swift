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

    private func testVideo() -> Video {
        Video(
            id: "dQw4w9WgXcQ",
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
