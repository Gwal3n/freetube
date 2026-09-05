import Foundation

struct LocalPlaylistSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let descriptionText: String?
    let sourcePlaylistID: String?
    let videoCount: Int
    let thumbnailURL: URL?
    let updatedAt: Date

    var isSavedFromYouTube: Bool { sourcePlaylistID != nil }
}
