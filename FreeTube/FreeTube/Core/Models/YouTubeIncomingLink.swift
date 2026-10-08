import Foundation

/// A public YouTube destination accepted from another app. Signed media URLs and arbitrary
/// websites are deliberately excluded: external links can only navigate or start playback.
enum YouTubeIncomingLink: Equatable {
    case video(String)
    case channel(String)
    case channelHandle(String)
    case playlist(String)

    static func parse(_ url: URL) -> Self? {
        if url.scheme?.lowercased() == "com.leshko.freetube" {
            guard url.host?.lowercased() == "open",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let sharedURL = URL(string: value),
                  sharedURL.scheme?.lowercased() != "com.leshko.freetube" else { return nil }
            return parseYouTubeURL(sharedURL)
        }
        return parseYouTubeURL(url)
    }

    private static func parseYouTubeURL(_ url: URL) -> Self? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
                  || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
        else { return nil }

        let path = components.path.split(separator: "/").map(String.init)
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if path.first?.lowercased() == "playlist",
               let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
               validIdentifier(list, minLength: 10, maxLength: 100) {
                return .playlist(list)
            }
            if path.first?.lowercased() == "watch",
               components.queryItems?.first(where: { $0.name == "v" })?.value == nil,
               let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
               validIdentifier(list, minLength: 10, maxLength: 100) {
                return .playlist(list)
            }
            if path.first?.lowercased() == "channel", path.count == 2,
               path[1].hasPrefix("UC"), validIdentifier(path[1], minLength: 24, maxLength: 24) {
                return .channel(path[1])
            }
            if path.count == 1, path[0].hasPrefix("@"),
               validHandle(String(path[0].dropFirst())) {
                return .channelHandle(path[0])
            }
        }
        if let id = YouTubeVideoLink.videoID(from: url.absoluteString) {
            return .video(id)
        }
        return nil
    }

    private static func validIdentifier(_ value: String, minLength: Int, maxLength: Int) -> Bool {
        guard (minLength...maxLength).contains(value.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validHandle(_ value: String) -> Bool {
        guard (3...30).contains(value.count) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
