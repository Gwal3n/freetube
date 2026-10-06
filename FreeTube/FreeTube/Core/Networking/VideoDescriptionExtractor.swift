import Foundation

/// Reads only the description from the already-fetched watch response. YouTube's command-run
/// offsets count UTF-16 code units, so NSString ranges preserve exact text/link alignment even
/// when a description contains emoji or composed characters. A malformed run is skipped while
/// the surrounding plain text remains visible.
nonisolated enum VideoDescriptionExtractor {
    static func extract(from data: Data) -> (text: String, parts: [VideoDescriptionPart])? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = value(
                in: root,
                at: ["contents", "twoColumnWatchNextResults", "results", "results", "contents"]
              ) as? [[String: Any]],
              let description = contents.compactMap({ item in
                  value(in: item, at: ["videoSecondaryInfoRenderer", "attributedDescription"])
                      as? [String: Any]
              }).first,
              let text = description["content"] as? String else { return nil }

        let source = text as NSString
        let commandRuns = description["commandRuns"] as? [[String: Any]] ?? []
        var parts: [VideoDescriptionPart] = []
        var cursor = 0

        for run in commandRuns {
            guard let start = run["startIndex"] as? Int,
                  let length = run["length"] as? Int,
                  start >= cursor,
                  length > 0,
                  start <= source.length,
                  length <= source.length - start else { continue }

            if start > cursor {
                parts.append(VideoDescriptionPart(
                    text: source.substring(with: NSRange(location: cursor, length: start - cursor)),
                    action: nil
                ))
            }
            let linkedText = source.substring(with: NSRange(location: start, length: length))
            parts.append(VideoDescriptionPart(
                text: linkedText,
                action: action(for: run, text: linkedText)
            ))
            cursor = start + length
        }

        if cursor < source.length {
            parts.append(VideoDescriptionPart(
                text: source.substring(from: cursor),
                action: nil
            ))
        }
        return (text, parts)
    }

    // MARK: - Link mapping

    private static func action(for run: [String: Any], text: String) -> VideoDescriptionPart.Action? {
        if let seconds = timestampSeconds(from: text) { return .seek(seconds) }
        guard let command = value(in: run, at: ["onTap", "innertubeCommand"]) as? [String: Any]
        else { return nil }

        if let rawURL = value(in: command, at: ["urlEndpoint", "url"]) as? String,
           let url = safeURL(from: rawURL) {
            return .externalURL(unwrappedRedirect(url))
        }
        if let videoID = value(in: command, at: ["watchEndpoint", "videoId"]) as? String,
           !videoID.isEmpty {
            if let seconds = value(in: command, at: ["watchEndpoint", "startTimeSeconds"]) as? Int {
                return .seek(TimeInterval(seconds))
            }
            return .video(videoID)
        }
        if let browseID = value(in: command, at: ["browseEndpoint", "browseId"]) as? String {
            if browseID.hasPrefix("UC") { return .channel(browseID) }
            if browseID.hasPrefix("VL") { return .playlist(browseID) }
        }
        if let rawURL = value(in: command, at: ["commandMetadata", "webCommandMetadata", "url"])
            as? String, let url = safeURL(from: rawURL) {
            return .externalURL(unwrappedRedirect(url))
        }
        return nil
    }

    private static func safeURL(from raw: String) -> URL? {
        let text = raw.hasPrefix("/") ? "https://www.youtube.com\(raw)" : raw
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }

    static func unwrappedRedirect(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com"),
              url.path == "/redirect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?
                .first(where: { $0.name == "q" || $0.name == "url" })?.value,
              let destination = safeURL(from: target) else { return url }
        return destination
    }

    static func timestampSeconds(from text: String) -> TimeInterval? {
        let components = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard components.count == 2 || components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let seconds = components.last.flatMap({ Int($0) }), seconds < 60 else { return nil }
        if components.count == 2 {
            guard let minutes = Int(components[0]) else { return nil }
            return TimeInterval(minutes * 60 + seconds)
        }
        guard let hours = Int(components[0]),
              let minutes = Int(components[1]), minutes < 60 else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    // MARK: - JSON access

    private static func value(in object: [String: Any], at path: [String]) -> Any? {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else { return nil }
            current = next
        }
        return current
    }
}
