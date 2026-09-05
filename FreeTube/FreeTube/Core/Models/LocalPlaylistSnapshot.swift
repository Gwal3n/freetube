import Foundation

struct LocalPlaylistSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let descriptionText: String?
    let sourcePlaylistID: String?
    let videoCount: Int
    let thumbnailURL: URL?
    let updatedAt: Date
    let metadataHydrationTotal: Int
    let metadataHydrationProcessed: Int
    let metadataHydrationFailures: Int

    var isSavedFromYouTube: Bool { sourcePlaylistID != nil }
    var isHydratingMetadata: Bool {
        metadataHydrationTotal > 0 && metadataHydrationProcessed < metadataHydrationTotal
    }
}
