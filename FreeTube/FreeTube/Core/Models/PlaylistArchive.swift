import Foundation

/// A selective, metadata-preserving export of local playlists. This is separate from the full
/// app backup so importing it never replaces subscriptions, history, settings, or other data.
struct PlaylistArchive: Codable, Sendable {
    static let currentVersion = 1
    static let fileType = "com.leshko.freetube.playlists"

    let type: String
    let formatVersion: Int
    let exportedAt: Date
    let playlists: [AppBackup.PlaylistRecord]

    init(playlists: [AppBackup.PlaylistRecord], exportedAt: Date = .now) {
        self.type = Self.fileType
        self.formatVersion = Self.currentVersion
        self.exportedAt = exportedAt
        self.playlists = playlists
    }
}
