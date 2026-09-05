import Foundation
import SwiftData

@available(iOS 17.0, *)
@Model
final class LocalPlaylistRecord {
    @Attribute(.unique) var playlistID: String
    var title: String
    var descriptionText: String?
    var createdAt: Date
    var updatedAt: Date
    var sourcePlaylistID: String?
    var metadataHydrationTotal: Int = 0
    var metadataHydrationProcessed: Int = 0
    var metadataHydrationFailures: Int = 0
    var sortPosition: Int = 0

    init(
        playlistID: String = UUID().uuidString,
        title: String,
        descriptionText: String? = nil,
        sourcePlaylistID: String? = nil
    ) {
        self.playlistID = playlistID
        self.title = title
        self.descriptionText = descriptionText
        createdAt = .now
        updatedAt = .now
        self.sourcePlaylistID = sourcePlaylistID
        metadataHydrationTotal = 0
        metadataHydrationProcessed = 0
        metadataHydrationFailures = 0
        sortPosition = 0
    }
}
