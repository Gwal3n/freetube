import Foundation
import XCTest
@testable import FreeTube

@MainActor
final class SearchLoadingTests: XCTestCase {
    func testOldPageCannotAppendToANewerSearch() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        model.query = "first"
        await model.submit()
        let page = Task { await model.loadMore() }
        await service.waitForPage()
        model.query = "second"
        await model.submit()
        service.completePage(.success(service.result("late")))
        await page.value
        XCTAssertEqual(model.results?.playlists.map(\.id), ["second"])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorState)
    }

    func testClearedSearchIgnoresOldPageErrors() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        model.query = "first"
        await model.submit()
        let page = Task { await model.loadMore() }
        await service.waitForPage()
        model.clearResults()
        service.completePage(.failure(URLError(.notConnectedToInternet)))
        await page.value
        XCTAssertNil(model.results)
        XCTAssertNil(model.errorState)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.paginationFailed)
    }

    func testInitialFailureHasARecoverableState() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        service.failSearch = true
        model.query = "query"
        await model.submit()
        XCTAssertTrue(model.didSearchFail)
        XCTAssertFalse(model.isLoading)
        service.failSearch = false
        await model.submit()
        XCTAssertFalse(model.didSearchFail)
        XCTAssertNil(model.errorState)
        XCTAssertNotNil(model.results)
    }

    func testPageFailureKeepsContentAndCanRetry() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        model.query = "first"
        await model.submit()
        let firstPageRevision = model.resultsRevision
        let page = Task { await model.loadMore() }
        await service.waitForPage()
        service.completePage(.failure(URLError(.notConnectedToInternet)))
        await page.value
        XCTAssertTrue(model.paginationFailed)
        XCTAssertEqual(model.results?.playlists.map(\.id), ["first"])
        let retry = Task { await model.loadMore() }
        await service.waitForPage()
        service.completePage(.success(service.result("next")))
        await retry.value
        XCTAssertFalse(model.paginationFailed)
        XCTAssertNil(model.errorState)
        XCTAssertEqual(model.results?.playlists.map(\.id), ["first", "next"])
        XCTAssertEqual(model.resultsRevision, firstPageRevision)

        await model.refresh()
        XCTAssertEqual(model.resultsRevision, firstPageRevision + 1)
    }
}

/// Continuations make request ordering deterministic without timers or real networking.
@MainActor
private final class ControlledSearchService: SearchServicing {
    var failSearch = false
    private var pendingPage: CheckedContinuation<SearchResult, Error>?
    private var pageStarted: CheckedContinuation<Void, Never>?

    func search(query: String) async throws -> SearchResult {
        if failSearch { throw URLError(.notConnectedToInternet) }
        return result(query)
    }

    func fetchMore(continuation: String) async throws -> SearchResult {
        try await withCheckedThrowingContinuation { continuation in
            pendingPage = continuation
            pageStarted?.resume()
            pageStarted = nil
        }
    }

    func autocomplete(query: String) async throws -> [SearchSuggestion] { [] }

    func waitForPage() async {
        if pendingPage != nil { return }
        await withCheckedContinuation { pageStarted = $0 }
    }

    func completePage(_ result: Result<SearchResult, Error>) {
        pendingPage?.resume(with: result)
        pendingPage = nil
    }

    func result(_ id: String) -> SearchResult {
        SearchResult(
            videos: [], channels: [],
            playlists: [Playlist(
                id: id, title: id, channelID: nil, channelName: nil,
                thumbnailURL: nil, videoCount: 0, descriptionText: nil, isOwnedByUser: false
            )],
            continuationToken: "next"
        )
    }
}
