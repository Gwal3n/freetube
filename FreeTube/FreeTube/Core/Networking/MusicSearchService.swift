import Foundation
import OSLog

protocol MusicSearchServicing: Sendable {
    func search(query: String) async throws -> SearchResult
}

/// Anonymous YouTube Music (`WEB_REMIX`) search. Single page; albums/podcasts omitted.
final class MusicSearchService: MusicSearchServicing {
    private let session: URLSession
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "MusicSearchService")

    private static let clientVersion = "1.20251015.03.00"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"

    nonisolated init(session: URLSession? = nil) {
        self.session = session ?? AnonymousURLSession.make()
    }

    /// Searches YouTube Music and returns songs, videos, artists, and playlists in relevance order.
    func search(query: String) async throws -> SearchResult {
        log.info("Music search query=\(query, privacy: .public)")
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            throw YouTubeServiceError.unknown(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": Self.clientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": query
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
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            log.error("Music search HTTP \(http.statusCode, privacy: .public)")
            if http.statusCode == 429 { throw YouTubeServiceError.rateLimited }
            throw YouTubeServiceError.network(URLError(.badServerResponse))
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeServiceError.decoding(error)
        }
        let items = Self.decode(root)
        log.info("Music search decoded \(items.count, privacy: .public) items")
        return SearchResult(items: items, continuationToken: nil)
    }

    // MARK: - Decoding

    static func decode(_ root: Any) -> [SearchHit] {
        let sections = array(root, "contents", "tabbedSearchResultsRenderer", "tabs", 0,
                             "tabRenderer", "content", "sectionListRenderer", "contents")
        var hits: [SearchHit] = []
        var seen = Set<String>()
        func append(_ hit: SearchHit?) {
            guard let hit, seen.insert(hit.id).inserted else { return }
            hits.append(hit)
        }
        for section in sections {
            if let card = value(section, "musicCardShelfRenderer") {
                append(cardHit(card))
                for item in array(card, "contents") {
                    append(value(item, "musicResponsiveListItemRenderer").flatMap(listItemHit))
                }
            }
            let items = array(section, "itemSectionRenderer", "contents")
                + array(section, "musicShelfRenderer", "contents")
            for item in items {
                append(value(item, "musicResponsiveListItemRenderer").flatMap(listItemHit))
            }
        }
        return hits
    }

    /// The highlighted top result. Its title links either to a watch page or an artist.
    private static func cardHit(_ card: Any) -> SearchHit? {
        let titleRuns = runs(value(card, "title"))
        let title = text(titleRuns)
        let subtitleRuns = runs(value(card, "subtitle"))
        guard !title.isEmpty, let firstRun = titleRuns.first else { return nil }
        if let videoID = value(firstRun, "navigationEndpoint", "watchEndpoint", "videoId") as? String {
            return .video(video(id: videoID, title: title, subtitleRuns: subtitleRuns))
        }
        if let browseID = value(firstRun, "navigationEndpoint", "browseEndpoint", "browseId") as? String,
           browseID.hasPrefix("UC") {
            return .channel(channel(id: browseID, name: title, thumbnailURL: thumbnail(card), subtitleRuns: subtitleRuns))
        }
        return nil
    }

    private static func listItemHit(_ item: Any) -> SearchHit? {
        let columns = array(item, "flexColumns").map {
            runs(value($0, "musicResponsiveListItemFlexColumnRenderer", "text"))
        }
        guard let titleRuns = columns.first else { return nil }
        let title = text(titleRuns)
        guard !title.isEmpty else { return nil }
        let subtitleRuns = columns.dropFirst().flatMap { $0 + [["text": " • "]] }

        let videoID = (value(item, "playlistItemData", "videoId") as? String)
            ?? (value(item, "overlay", "musicItemThumbnailOverlayRenderer", "content",
                      "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId") as? String)
        if let videoID {
            return .video(video(id: videoID, title: title, subtitleRuns: subtitleRuns))
        }

        guard let browseID = value(item, "navigationEndpoint", "browseEndpoint", "browseId") as? String else {
            return nil
        }
        if browseID.hasPrefix("UC") {
            return .channel(channel(id: browseID, name: title, thumbnailURL: thumbnail(item), subtitleRuns: subtitleRuns))
        }
        if browseID.hasPrefix("VL") {
            let parts = parts(subtitleRuns)
            return .playlist(Playlist(
                id: String(browseID.dropFirst(2)),
                title: title,
                channelID: nil,
                channelName: parts.dropFirst().first,
                thumbnailURL: thumbnail(item),
                videoCount: parts.lazy.compactMap(songCount).first,
                descriptionText: nil,
                isOwnedByUser: false
            ))
        }
        return nil
    }

    // MARK: - Mapping

    private static let kindLabels: Set<String> = ["Song", "Video", "Episode", "Artist", "Profile", "Playlist"]

    private static func video(id: String, title: String, subtitleRuns: [[String: Any]]) -> Video {
        let parts = parts(subtitleRuns)
        let owner = subtitleRuns.first { run in
            (value(run, "navigationEndpoint", "browseEndpoint", "browseId") as? String)?.hasPrefix("UC") == true
        }
        let ownerID = owner.flatMap { value($0, "navigationEndpoint", "browseEndpoint", "browseId") as? String }
        // Episodes read "Episode • <date> • <show>", so their owner is the last part.
        let ownerName = (owner?["text"] as? String)
            ?? (parts.first == "Episode" ? parts.last : nil)
            ?? parts.first { !kindLabels.contains($0) && !isCount($0) && !isDuration($0) }
        let viewCount = parts.lazy.filter(isCount).compactMap {
            Mappers.parseAbbreviatedCount($0.replacingOccurrences(of: "plays", with: "views"))
        }.first
        let duration = parts.lazy.filter(isDuration).compactMap { Mappers.duration(from: $0) }.first
        return Video(
            id: id,
            title: title,
            channelID: ownerID ?? "",
            channelName: ownerName ?? "",
            channelThumbnailURL: nil,
            thumbnailURL: Mappers.canonicalThumbnailURL(for: id),
            duration: duration,
            viewCount: viewCount,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }

    private static func channel(id: String, name: String, thumbnailURL: URL?, subtitleRuns: [[String: Any]]) -> Channel {
        let handle = parts(subtitleRuns).first { $0.hasPrefix("@") }
        return Channel(
            id: id,
            name: name,
            handle: handle,
            thumbnailURL: thumbnailURL,
            bannerURL: nil,
            subscriberCount: nil,
            videoCount: nil,
            isSubscribed: false,
            descriptionText: nil
        )
    }

    private static func isCount(_ part: String) -> Bool {
        part.hasSuffix(" views") || part.hasSuffix(" plays")
    }

    private static func isDuration(_ part: String) -> Bool {
        part.range(of: #"^\d{1,2}(:\d{2}){1,2}$"#, options: .regularExpression) != nil
    }

    private static func songCount(_ part: String) -> Int? {
        guard part.hasSuffix(" songs") || part.hasSuffix(" tracks") else { return nil }
        return Int(part.filter(\.isWholeNumber))
    }

    // MARK: - JSON helpers

    /// Visible text segments of a run list, without the " • " separators.
    private static func parts(_ runs: [[String: Any]]) -> [String] {
        runs.compactMap { $0["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" }
    }

    private static func text(_ runs: [[String: Any]]) -> String {
        runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func runs(_ object: Any?) -> [[String: Any]] {
        (value(object, "runs") as? [[String: Any]]) ?? []
    }

    private static func thumbnail(_ object: Any) -> URL? {
        let thumbnails = (value(object, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails") as? [[String: Any]]) ?? []
        return thumbnails.last.flatMap { $0["url"] as? String }.flatMap(URL.init(string:))
    }

    private static func array(_ object: Any?, _ path: Any...) -> [Any] {
        (walk(object, path) as? [Any]) ?? []
    }

    private static func value(_ object: Any?, _ path: Any...) -> Any? {
        walk(object, path)
    }

    private static func walk(_ object: Any?, _ path: [Any]) -> Any? {
        var current = object
        for key in path {
            if let key = key as? String {
                current = (current as? [String: Any])?[key]
            } else if let index = key as? Int {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }
}
