import Foundation

struct AppBackup: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let settings: [String: SettingValue]
    let subscriptions: [LocalSubscription]
    let playlists: [PlaylistRecord]
    let watchHistory: [WatchHistorySnapshot]
    let searchHistory: [SearchRecord]
    let favoriteVideos: [FavoriteVideoRecord]
    let favoritePlaylists: [FavoritePlaylistRecord]

    enum SettingValue: Codable, Sendable {
        case boolean(Bool)
        case integer(Int)
        case number(Double)
        case text(String)
    }

    struct PlaylistRecord: Codable, Sendable {
        let title: String
        let descriptionText: String?
        let sourcePlaylistID: String?
        let videos: [Video]
    }

    struct SearchRecord: Codable, Sendable {
        let query: String
        let searchedAt: Date
    }

    struct FavoriteVideoRecord: Codable, Sendable {
        let videoID: String
        let title: String
        let channelName: String
        let thumbnailURL: URL?
        let savedAt: Date
    }

    struct FavoritePlaylistRecord: Codable, Sendable {
        let playlistID: String
        let title: String
        let channelName: String
        let thumbnailURL: URL?
        let videoCount: Int?
        let savedAt: Date
    }
}
