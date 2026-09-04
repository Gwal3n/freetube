import Foundation
import OSLog
import YouTubeKit

struct SearchResult: Sendable {
    let videos: [Video]
    let channels: [Channel]
    let playlists: [Playlist]
    let continuationToken: String?
}

protocol SearchServicing: Sendable {
    func search(query: String, restricted: Bool) async throws -> SearchResult
    func fetchMore(continuation: String) async throws -> SearchResult
    func autocomplete(query: String) async throws -> [SearchSuggestion]
}

/// Wraps `SearchResponse` (+Continuation, +Restricted) and `AutoCompletionResponse`.
final class SearchService: SearchServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "SearchService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    func search(query: String, restricted: Bool) async throws -> SearchResult {
        log.info("Search query=\(query, privacy: .public) restricted=\(restricted, privacy: .public)")
        do {
            if restricted {
                let response = try await AppRestrictedSearchResponse.sendThrowingRequest(
                    youtubeModel: client.model,
                    data: [.query: query]
                )
                return mapResults(response.results, continuation: response.continuationToken)
            } else {
                let response = try await AppSearchResponse.sendThrowingRequest(
                    youtubeModel: client.model,
                    data: [.query: query]
                )
                return mapResults(response.results, continuation: response.continuationToken)
            }
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
        var videos: [Video] = []
        var channels: [Channel] = []
        var playlists: [Playlist] = []
        for result in results {
            if let yt = result as? YTVideo {
                videos.append(Mappers.video(from: yt))
            } else if let yt = result as? YTChannel {
                channels.append(Mappers.channel(from: yt))
            } else if let yt = result as? YTPlaylist {
                playlists.append(Mappers.playlist(from: yt))
            }
        }
        return SearchResult(videos: videos, channels: channels, playlists: playlists, continuationToken: continuation)
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

private struct AppRestrictedSearchResponse: YouTubeResponse {
    static let headersType: HeaderTypes = .restrictedSearch
    static let parametersValidationList: ValidationList = [.query: .existenceValidator]
    var results: [any YTSearchResult] = []
    var continuationToken: String?

    static func decodeJSON(json: JSON) -> Self {
        let decoded = SearchResponseDecoder.decodeSections(
            json["contents", "twoColumnSearchResultsRenderer", "primaryContents", "sectionListRenderer", "contents"].arrayValue
        )
        return Self(results: decoded.results, continuationToken: decoded.continuationToken)
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
