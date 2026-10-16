import Foundation
import OSLog

/// Best-effort fallback when YouTubeKit's channel-header decoder omits the avatar. It reads only
/// the public `og:image` tag and never needs a YouTube account, cookie, or Data API key.
struct ChannelAvatarService {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "ChannelAvatar")

    func fetchAvatar(id: String) async -> URL? {
        guard let channelURL = URL(string: "https://www.youtube.com/channel")?
            .appendingPathComponent(id) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            var request = URLRequest(url: channelURL)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 5_000_000,
                  let html = String(data: data, encoding: .utf8) else { return nil }
            let avatar = Self.avatarURL(in: html)
            if avatar == nil {
                log.notice("Public channel page had no usable avatar for \(id, privacy: .public)")
            } else {
                log.info("Public avatar fallback resolved for \(id, privacy: .public)")
            }
            return avatar
        } catch {
            log.notice("Public avatar fallback unavailable for \(id, privacy: .public)")
            return nil
        }
    }

    static func avatarURL(in html: String) -> URL? {
        let tagPattern = #"<meta\b(?=[^>]*\bproperty\s*=\s*["']og:image["'])[^>]*>"#
        let contentPattern = #"\bcontent\s*=\s*["']([^"']+)["']"#
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive),
              let tagMatch = tagRegex.firstMatch(
                in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              let tagRange = Range(tagMatch.range, in: html) else { return nil }
        let tag = String(html[tagRange])
        guard let contentRegex = try? NSRegularExpression(pattern: contentPattern, options: .caseInsensitive),
              let contentMatch = contentRegex.firstMatch(
                in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)
              ),
              let contentRange = Range(contentMatch.range(at: 1), in: tag) else { return nil }
        let rawURL = tag[contentRange].replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: rawURL), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "yt3.googleusercontent.com" || host == "yt3.ggpht.com"
                || host.hasSuffix(".ytimg.com") else { return nil }
        return url
    }
}
