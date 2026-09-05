import Foundation

struct LocalPlaylistSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let videoCount: Int
    let thumbnailURL: URL?
    let updatedAt: Date
}
