import Foundation

/// Builds an anonymous YouTube temporary-playlist link from local playlist membership.
/// YouTube accepts at most 50 IDs in this flow; never imply a larger list was fully shared.
@available(iOS 17.0, *)
struct TemporaryYouTubePlaylistShare {
    static let maximumVideoCount = 50

    let url: URL
    let includedCount: Int
    let availableCount: Int

    static func make(videoIDs: [String]) -> Self? {
        guard !videoIDs.isEmpty else { return nil }
        let allowedIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard videoIDs.allSatisfy({ id in
            id.count == 11 && id.unicodeScalars.allSatisfy { scalar in
                allowedIDCharacters.contains(scalar)
            }
        }) else { return nil }

        let selectedIDs = Array(videoIDs.prefix(maximumVideoCount))
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch_videos"
        components.queryItems = [URLQueryItem(name: "video_ids", value: selectedIDs.joined(separator: ","))]
        guard let url = components.url else { return nil }

        return Self(url: url, includedCount: selectedIDs.count, availableCount: videoIDs.count)
    }
}
