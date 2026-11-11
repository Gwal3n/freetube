import Foundation
import OSLog
import YouTubeKit

/// Search page with hits kept in YouTube relevance order (videos, channels, and playlists mixed).
struct SearchResult: Sendable {
    let items: [SearchHit]
    let continuationToken: String?

    var videos: [Video] {
        items.compactMap {
            if case .video(let video) = $0 { return video }
            return nil
        }
    }

    var channels: [Channel] {
        items.compactMap {
            if case .channel(let channel) = $0 { return channel }
            return nil
        }
    }

    var playlists: [Playlist] {
        items.compactMap {
            if case .playlist(let playlist) = $0 { return playlist }
            return nil
        }
    }

    init(items: [SearchHit], continuationToken: String?) {
        self.items = items
        self.continuationToken = continuationToken
    }
}

protocol SearchServicing: Sendable {
    func search(query: String, params: String?) async throws -> SearchResult
    func fetchMore(continuation: String) async throws -> SearchResult
    func autocomplete(query: String) async throws -> [SearchSuggestion]
}

extension SearchServicing {
    func search(query: String) async throws -> SearchResult {
        try await search(query: query, params: nil)
    }
}

/// Wraps `SearchResponse` (+Continuation) and `AutoCompletionResponse`.
final class SearchService: SearchServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SearchService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    func search(query: String, params: String? = nil) async throws -> SearchResult {
        let trimmedParams = params?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedParams = (trimmedParams?.isEmpty == false) ? trimmedParams : nil
        log.info(
            "Search query=\(query, privacy: .public) params=\(resolvedParams != nil ? "yes" : "no", privacy: .public)"
        )

        var data: YouTubeResponse.RequestData = [.query: query]
        if let resolvedParams {
            data[.params] = resolvedParams
            // Stock YouTubeKit search bodies have no `params` slot. Temporarily install the same
            // shape as restricted search so filter tokens can be omitted entirely when inactive.
            let previousHeaders = client.model.customHeaders[.search]
            client.model.customHeaders[.search] = Self.searchHeadersWithParams()
            defer { client.model.customHeaders[.search] = previousHeaders }
            do {
                let response = try await AppSearchResponse.sendThrowingRequest(
                    youtubeModel: client.model,
                    data: data
                )
                return mapResults(response.results, continuation: response.continuationToken)
            } catch {
                throw YouTubeServiceError.network(error)
            }
        }

        do {
            let response = try await AppSearchResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: data
            )
            return mapResults(response.results, continuation: response.continuationToken)
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchMore(continuation: String) async throws -> SearchResult {
        do {
            let response = try await AppSearchContinuationResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.continuation: continuation]
            )
            return mapResults(response.results, continuation: response.continuationToken)
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    func autocomplete(query: String) async throws -> [SearchSuggestion] {
        do {
            let response = try await AutoCompletionResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.query: query]
            )
            return response.autoCompletionEntries.map { SearchSuggestion(text: $0) }
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    private func mapResults(_ results: [any YTSearchResult], continuation: String?) -> SearchResult {
        let items: [SearchHit] = results.compactMap { result in
            if let yt = result as? YTVideo {
                return .video(Mappers.video(from: yt))
            }
            if let yt = result as? YTChannel {
                return .channel(Mappers.channel(from: yt))
            }
            if let yt = result as? YTPlaylist {
                return .playlist(Mappers.playlist(from: yt))
            }
            return nil
        }
        return SearchResult(items: items, continuationToken: continuation)
    }

    /// YouTubeKit's default search body has no `params` field. This mirrors that body and inserts
    /// the same params slot restricted-search already uses.
    private static func searchHeadersWithParams() -> HeadersList {
        let model = YouTubeKitClient.shared.model
        let language = model.selectedLocaleLanguageCode
        let country = model.selectedLocaleCountryCode.uppercased()
        let locale = model.selectedLocale
        return HeadersList(
            url: URL(string: "https://www.youtube.com/youtubei/v1/search")!,
            method: .POST,
            headers: [
                .init(name: "Accept", content: "*/*"),
                .init(name: "Accept-Encoding", content: "gzip, deflate, br"),
                .init(name: "Host", content: "www.youtube.com"),
                .init(name: "User-Agent", content: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"),
                .init(name: "Accept-Language", content: "\(locale);q=0.9"),
                .init(name: "Origin", content: "https://www.youtube.com/"),
                .init(name: "Referer", content: "https://www.youtube.com/"),
                .init(name: "Connection", content: "keep-alive"),
                .init(name: "Content-Type", content: "application/json"),
                .init(name: "X-Youtube-Client-Name", content: "1"),
                .init(name: "Priority", content: "u=3, i"),
                .init(name: "X-Origin", content: "https://www.youtube.com")
            ],
            addQueryAfterParts: [
                .init(index: 0, encode: true, content: .query),
                .init(index: 1, encode: false, content: .query),
                .init(index: 2, encode: false, content: .params, optional: false)
            ],
            httpBody: [
                "{\"context\":{\"client\":{\"hl\":\"\(language)\",\"gl\":\"\(country)\",\"userAgent\":\"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15,gzip(gfe)\",\"clientName\":\"WEB\",\"clientVersion\":\"2.20260213.01.00\",\"osName\":\"Macintosh\",\"osVersion\":\"10_15_7\",\"timeZone\":\"Europe/Zurich\",\"browserName\":\"Safari\",\"browserVersion\":\"16.2\",\"utcOffsetMinutes\":60,\"mainAppWebInfo\":{\"graftUrl\":\"/results?search_query=",
                "\"}},\"user\":{\"lockedSafetyMode\":false},\"request\":{\"useSsl\":true,\"internalExperimentFlags\":[],\"consistencyTokenJars\":[]}},\"query\":\"",
                "\", \"params\": \"",
                "\"}"
            ],
            parameters: [
                .init(name: "prettyPrint", content: "false")
            ]
        )
    }
}

/// Search decoder that supplements YouTubeKit's legacy renderer handling with the modern
/// `lockupViewModel` shape now used for playlist results.
private struct AppSearchResponse: YouTubeResponse {
    static let headersType: HeaderTypes = .search
    static let parametersValidationList: ValidationList = [.query: .existenceValidator]
    var results: [any YTSearchResult] = []
    var continuationToken: String?

    static func decodeJSON(json: JSON) -> Self {
        let sections = json["contents", "twoColumnSearchResultsRenderer", "primaryContents", "sectionListRenderer", "contents"].arrayValue
        return SearchResponseDecoder.decodeSections(sections)
    }
}

private struct AppSearchContinuationResponse: ResponseContinuation {
    static let headersType: HeaderTypes = .searchContinuationHeaders
    static let parametersValidationList: ValidationList = [.continuation: .existenceValidator]
    var continuationToken: String?
    var results: [any YTSearchResult] = []

    static func decodeJSON(json: JSON) -> Self {
        let commands = json["onResponseReceivedCommands"].arrayValue
            + json["onResponseReceivedEndpoints"].arrayValue
        let sections = commands.flatMap {
            $0["appendContinuationItemsAction", "continuationItems"].arrayValue
        }
        let decoded = SearchResponseDecoder.decodeSections(sections)
        return Self(continuationToken: decoded.continuationToken, results: decoded.results)
    }
}

private enum SearchResponseDecoder {
    static func decodeSections(_ sections: [JSON]) -> AppSearchResponse {
        var response = AppSearchResponse()
        for section in sections {
            if let token = section["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"].string {
                response.continuationToken = token
                continue
            }
            let items = section["itemSectionRenderer", "contents"].array
                ?? section["shelfRenderer", "content", "verticalListRenderer", "items"].array
                ?? [section]
            if let token = items.compactMap({
                $0["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"].string
            }).first {
                response.continuationToken = token
            }
            response.results.append(contentsOf: decodeItems(items))
        }
        return response
    }

    private static func decodeItems(_ items: [JSON]) -> [any YTSearchResult] {
        items.flatMap { item -> [any YTSearchResult] in
            if let video = YTVideo.decodeJSON(json: item["videoRenderer"]) { return [video] }
            if let channel = YTChannel.decodeJSON(json: item["channelRenderer"]) { return [channel] }
            if let playlist = YTPlaylist.decodeJSON(json: item["playlistRenderer"]) { return [playlist] }
            let lockup = item["lockupViewModel"]
            if let playlist = YTPlaylist.decodeLockupJSON(json: lockup) { return [playlist] }
            if let video = YTVideo.decodeLockupJSON(json: lockup) { return [video] }
            if item["richItemRenderer", "content"].exists() {
                return decodeItems([item["richItemRenderer", "content"]])
            }
            if let nested = item["shelfRenderer", "content", "verticalListRenderer", "items"].array {
                return decodeItems(nested)
            }
            return []
        }
    }
}
