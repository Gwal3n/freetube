import Foundation

protocol LiveChatServicing: Sendable {
    func bootstrap(videoID: String) async throws -> LiveChatBootstrapExtractor.Bootstrap
    func poll(
        continuation: String,
        apiKey: String,
        clientVersion: String
    ) async throws -> LiveChatPage
}

/// Anonymous read-only live chat via InnerTube `get_live_chat`. No send path.
final class LiveChatService: LiveChatServicing {
    private let session: URLSession
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "LiveChatService")

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"

    nonisolated init(session: URLSession? = nil) {
        self.session = session ?? AnonymousURLSession.make {
            $0.timeoutIntervalForRequest = 15
            $0.timeoutIntervalForResource = 20
        }
    }

    /// Loads the public `live_chat` page and extracts the first continuation.
    func bootstrap(videoID: String) async throws -> LiveChatBootstrapExtractor.Bootstrap {
        guard videoID.count == 11 else { throw YouTubeServiceError.videoUnavailable }
        log.info("Bootstrapping live chat for \(videoID, privacy: .public)")
        guard var components = URLComponents(string: "https://www.youtube.com/live_chat") else {
            throw YouTubeServiceError.unknown(URLError(.badURL))
        }
        components.queryItems = [
            URLQueryItem(name: "is_popout", value: "1"),
            URLQueryItem(name: "v", value: videoID)
        ]
        guard let url = components.url else { throw YouTubeServiceError.unknown(URLError(.badURL)) }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YouTubeServiceError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              data.count <= 8_000_000,
              let html = String(data: data, encoding: .utf8) else {
            log.error("Live chat page HTTP \(status, privacy: .public) for \(videoID, privacy: .public)")
            if status == 429 { throw YouTubeServiceError.rateLimited }
            throw YouTubeServiceError.videoUnavailable
        }
        guard let bootstrap = LiveChatBootstrapExtractor.extract(from: html) else {
            log.notice("No live chat continuation for \(videoID, privacy: .public)")
            throw YouTubeServiceError.videoUnavailable
        }
        log.info("Live chat bootstrapped for \(videoID, privacy: .public)")
        return bootstrap
    }

    /// One continuation poll. Pass the previous page's continuation; never log the token.
    func poll(
        continuation: String,
        apiKey: String,
        clientVersion: String
    ) async throws -> LiveChatPage {
        guard !continuation.isEmpty, !apiKey.isEmpty else {
            throw YouTubeServiceError.videoUnavailable
        }
        guard var components = URLComponents(
            string: "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat"
        ) else {
            throw YouTubeServiceError.unknown(URLError(.badURL))
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let url = components.url else { throw YouTubeServiceError.unknown(URLError(.badURL)) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": clientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "continuation": continuation
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw YouTubeServiceError.unknown(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YouTubeServiceError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            log.error("get_live_chat HTTP \(status, privacy: .public)")
            if status == 429 { throw YouTubeServiceError.rateLimited }
            if status == 403 || status == 400 { throw YouTubeServiceError.videoUnavailable }
            throw YouTubeServiceError.network(URLError(.badServerResponse))
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeServiceError.decoding(error)
        }
        let page = LiveChatPageDecoder.decode(root)
        log.info(
            "Live chat poll messages=\(page.messages.count, privacy: .public) hasContinuation=\(page.continuation != nil, privacy: .public)"
        )
        return page
    }
}
