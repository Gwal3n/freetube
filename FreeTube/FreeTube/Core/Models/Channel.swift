import Foundation

struct Channel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let handle: String?
    let thumbnailURL: URL?
    let bannerURL: URL?
    let subscriberCount: Int?
    let videoCount: Int?
    let isSubscribed: Bool
    let descriptionText: String?

    var youtubeURL: URL? {
        let channelID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/channel")?.appendingPathComponent(channelID)
    }
}
