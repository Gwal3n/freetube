import Foundation

/// Pulls the public Innertube key, WEB client version, and first live-chat continuation from a
/// `live_chat` HTML page. Tokens are request metadata, never persisted.
nonisolated enum LiveChatBootstrapExtractor {
    struct Bootstrap: Sendable {
        let apiKey: String
        let clientVersion: String
        let continuation: String
    }

    static func extract(from html: String) -> Bootstrap? {
        guard let apiKey = firstMatch(in: html, pattern: #"INNERTUBE_API_KEY"\s*:\s*"([^"]+)""#),
              !apiKey.isEmpty else { return nil }
        let clientVersion = firstMatch(
            in: html,
            pattern: #"INNERTUBE_CONTEXT_CLIENT_VERSION"\s*:\s*"([^"]+)""#
        ) ?? firstMatch(in: html, pattern: #"clientVersion"\s*:\s*"(2\.\d[^"]*)""#)
            ?? "2.20251119.01.00"
        guard let continuation = continuationToken(in: html), !continuation.isEmpty else {
            return nil
        }
        return Bootstrap(apiKey: apiKey, clientVersion: clientVersion, continuation: continuation)
    }

    /// Prefer a continuation nested under live-chat renderers so watch-page noise is ignored.
    private static func continuationToken(in html: String) -> String? {
        let anchors = [
            "liveChatContinuation",
            "liveChatRenderer",
            "timedContinuationData",
            "invalidationContinuationData",
            "reloadContinuationData"
        ]
        for anchor in anchors {
            guard let range = html.range(of: anchor) else { continue }
            let window = String(html[range.lowerBound...].prefix(2_500))
            if let token = firstMatch(in: window, pattern: #"continuation"\s*:\s*"([^"]+)""#),
               token.count > 20 {
                return token
            }
        }
        return firstMatch(in: html, pattern: #"continuation"\s*:\s*"([0-9A-Za-z_\-%]{40,})""#)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[tokenRange])
    }
}
