import XCTest
@testable import FreeTube

final class AppBackupTests: XCTestCase {
    func testBackupJSONRoundTripPreservesHydratedPlaylistData() throws {
        let exportDate = Date(timeIntervalSince1970: 1_700_000_000)
        let video = Video(
            id: "video-id",
            title: "Resolved title",
            channelID: "channel-id",
            channelName: "Resolved channel",
            channelThumbnailURL: URL(string: "https://example.com/channel.jpg"),
            thumbnailURL: URL(string: "https://example.com/video.jpg"),
            duration: 321,
            viewCount: 12_345,
            publishedAt: exportDate,
            publishedRelative: "2 years ago",
            descriptionSnippet: "Resolved description",
            isLive: false,
            isShort: false
        )
        var backup = AppBackup(
            formatVersion: 1,
            exportedAt: exportDate,
            settings: ["autoplayNext": .boolean(true), "preferredQuality": .integer(1080)],
            subscriptions: [],
            playlists: [.init(title: "Saved playlist", descriptionText: "Description", sourcePlaylistID: "PL123", videos: [video])],
            watchHistory: [],
            searchHistory: [.init(query: "swift", searchedAt: exportDate)],
            favoriteVideos: [],
            favoritePlaylists: []
        )
        let groupID = UUID(uuidString: "CB0B5106-201B-4A32-87AD-1299657D7130")!
        backup.subscriptionGroups = [SubscriptionGroup(id: groupID, name: "Science", channelIDs: ["channel-id"])]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(AppBackup.self, from: data)

        XCTAssertEqual(restored.formatVersion, 1)
        XCTAssertEqual(restored.playlists.first?.sourcePlaylistID, "PL123")
        XCTAssertEqual(restored.playlists.first?.videos.first, video)
        XCTAssertEqual(restored.searchHistory.first?.query, "swift")
        XCTAssertEqual(restored.subscriptionGroups, backup.subscriptionGroups)
        guard case .some(.boolean(true)) = restored.settings["autoplayNext"] else {
            return XCTFail("Boolean setting did not survive the backup round trip")
        }
        guard case .some(.integer(1080)) = restored.settings["preferredQuality"] else {
            return XCTFail("Integer setting did not survive the backup round trip")
        }
    }

    func testOldBackupWithoutGroupsStillDecodes() throws {
        let data = try XCTUnwrap("""
        {
          "formatVersion": 1,
          "exportedAt": "2023-11-14T22:13:20Z",
          "settings": {},
          "subscriptions": [],
          "playlists": [],
          "watchHistory": [],
          "searchHistory": [],
          "favoriteVideos": [],
          "favoritePlaylists": []
        }
        """.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNil(try decoder.decode(AppBackup.self, from: data).subscriptionGroups)
    }
}
