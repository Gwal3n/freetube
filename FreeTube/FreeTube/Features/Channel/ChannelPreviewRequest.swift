import Foundation

/// Lightweight seed for the channel preview sheet. Full stats load through `ChannelPreviewMetadataStore`.
nonisolated struct ChannelPreviewRequest: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?

    init(id: String, name: String, thumbnailURL: URL? = nil) {
        self.id = id
        self.name = name
        self.thumbnailURL = thumbnailURL
    }

    var seedChannel: Channel {
        Channel(
            id: id,
            name: name,
            handle: nil,
            thumbnailURL: thumbnailURL,
            bannerURL: nil,
            subscriberCount: nil,
            videoCount: nil,
            isSubscribed: false,
            descriptionText: nil
        )
    }
}
