import Foundation

/// Parses a YouTube video link without making a request or accepting arbitrary hosts.
enum YouTubeVideoLink {
    static func videoID(from text: String, allowBareID: Bool = false) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if allowBareID, isValidVideoID(trimmed) { return trimmed }

        let lowercased = trimmed.lowercased()
        let candidate: String
        if lowercased.hasPrefix("youtube.com/")
            || lowercased.hasPrefix("www.youtube.com/")
            || lowercased.hasPrefix("m.youtube.com/")
            || lowercased.hasPrefix("music.youtube.com/")
            || lowercased.hasPrefix("youtu.be/") {
            candidate = "https://" + trimmed
        } else {
            candidate = trimmed
        }

        guard let components = URLComponents(string: candidate),
              let rawHost = components.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let pathParts = components.path.split(separator: "/").map(String.init)
        let possibleID: String?

        if host == "youtu.be" {
            possibleID = pathParts.first
        } else if host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com") {
            if components.path == "/watch" {
                possibleID = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if let route = pathParts.first?.lowercased(),
                      ["shorts", "embed", "live"].contains(route),
                      pathParts.count > 1 {
                possibleID = pathParts[1]
            } else {
                possibleID = nil
            }
        } else {
            possibleID = nil
        }

        guard let id = possibleID, isValidVideoID(id) else { return nil }
        return id
    }

    private static func isValidVideoID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        return id.unicodeScalars.allSatisfy(allowed.contains)
    }
}
