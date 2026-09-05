import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class LocalPlaylistRecord {
    @Attribute(.unique) var playlistID: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var sourcePlaylistID: String?

    init(playlistID: String = UUID().uuidString, title: String, sourcePlaylistID: String? = nil) {
        self.playlistID = playlistID
        self.title = title
        createdAt = .now
        updatedAt = .now
        self.sourcePlaylistID = sourcePlaylistID
    }
}
