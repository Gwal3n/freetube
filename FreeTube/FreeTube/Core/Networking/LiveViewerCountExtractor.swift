import Foundation

/// Reads the watch page's explicitly live-labelled count from the same response as video details.
/// Player `videoDetails.viewCount` is a total view count and must never substitute for viewers.
nonisolated enum LiveViewerCountExtractor {
    static func extract(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let columns = root["contents"] as? [String: Any],
              let results = columns["twoColumnWatchNextResults"] as? [String: Any],
              let outer = results["results"] as? [String: Any],
              let inner = outer["results"] as? [String: Any],
              let contents = inner["contents"] as? [[String: Any]] else { return nil }

        for content in contents {
            guard let primary = content["videoPrimaryInfoRenderer"] as? [String: Any],
                  let count = primary["viewCount"] as? [String: Any],
                  let renderer = count["videoViewCountRenderer"] as? [String: Any],
                  renderer["isLive"] as? Bool == true,
                  let label = renderer["viewCount"] as? [String: Any] else { continue }

            let runs = (label["runs"] as? [[String: Any]]) ?? []
            let runText = runs.compactMap { $0["text"] as? String }.joined()
            let simpleText = (label["simpleText"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = (simpleText?.isEmpty == false ? simpleText ?? "" : runText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            return text
        }
        return nil
    }
}
