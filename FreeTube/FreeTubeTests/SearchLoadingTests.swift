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

    func testServerFilterChangeResearchesWithParams() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        model.query = "cats"
        await model.submit()
        XCTAssertEqual(service.searches.map(\.params), [nil])
        XCTAssertTrue(model.applyServerMirroredLocally)

        let beforeFilters = model.videoFilters
        model.videoFilters.uploaded = .pastWeek
        XCTAssertNotNil(model.results)
        model.serverFiltersDidChange(from: beforeFilters)
        await waitUntil(service.searches.count == 2)

        XCTAssertEqual(service.searches.last?.params, model.videoFilters.serverParams)
        XCTAssertFalse(model.applyServerMirroredLocally)
        XCTAssertEqual(model.resultsRevision, 2)
    }

    func testServerFilterFailureFallsBackToPlainQuery() async {
        let service = ControlledSearchService()
        let model = SearchViewModel(service: service)
        model.query = "cats"
        await model.submit()

        service.failWhenParamsPresent = true
        let beforeFilters = model.videoFilters
        model.videoFilters.length = .underFourMinutes
        model.serverFiltersDidChange(from: beforeFilters)
        await waitUntil(service.searches.count >= 3)

        XCTAssertEqual(service.searches.dropFirst().map(\.params).contains(where: { $0 != nil }), true)
        XCTAssertEqual(service.searches.last?.params, nil)
        XCTAssertTrue(model.applyServerMirroredLocally)
        XCTAssertEqual(
            model.errorState?.message,
            "Server filters unavailable. Using local filters."
        )
        XCTAssertNotNil(model.results)
        XCTAssertFalse(model.didSearchFail)
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 1
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

/// Continuations make request ordering deterministic without timers or real networking.
@MainActor
private final class ControlledSearchService: SearchServicing {
    var failSearch = false
    var failWhenParamsPresent = false
    private(set) var searches: [(query: String, params: String?)] = []
    private var pendingPage: CheckedContinuation<SearchResult, Error>?
    private var pageStarted: CheckedContinuation<Void, Never>?

    func search(query: String, params: String?) async throws -> SearchResult {
        searches.append((query, params))
        if failSearch { throw URLError(.notConnectedToInternet) }
        if failWhenParamsPresent, params != nil {
            throw URLError(.badServerResponse)
        }
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
