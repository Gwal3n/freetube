import XCTest
@testable import FreeTube

@MainActor
final class DeArrowTests: XCTestCase {
    func testTrustedTitleAndThumbnailAreSelected() throws {
        let value = try payload("""
        {"titles":[{"title":"  Descriptive title  ","original":false,"votes":0,"locked":false}],
         "thumbnails":[{"timestamp":12.5,"original":false,"votes":2,"locked":false}]}
        """)
        XCTAssertEqual(value.replacementTitle, "Descriptive title")
        XCTAssertEqual(time(value), 12.5)
    }

    func testNegativeVotesAreRejectedUnlessLocked() throws {
        let rejected = try payload("""
        {"titles":[{"title":"Untrusted","original":false,"votes":-1,"locked":false}],
         "thumbnails":[{"timestamp":12,"original":false,"votes":-1,"locked":false}]}
        """)
        XCTAssertNil(rejected.replacementTitle)
        XCTAssertNil(time(rejected, fallback: false))
        XCTAssertNotNil(time(rejected, fallback: true))

        let locked = try payload("""
        {"titles":[{"title":"Approved","original":false,"votes":-1,"locked":true}],
         "thumbnails":[{"timestamp":12,"original":false,"votes":-1,"locked":true}]}
        """)
        XCTAssertEqual(locked.replacementTitle, "Approved")
        XCTAssertEqual(time(locked), 12)
    }

    func testExplicitOriginalNeverTriggersRandomFallback() throws {
        let value = try payload("""
        {"titles":[{"title":"Original","original":true,"votes":5,"locked":false}],
         "thumbnails":[{"timestamp":null,"original":true,"votes":5,"locked":false}]}
        """)
        XCTAssertNil(value.replacementTitle)
        XCTAssertNil(time(value, fallback: true))
    }

    func testRandomFallbackIsStableAndAvoidsEndCredits() {
        let first = time(.empty, fallback: true)
        XCTAssertEqual(first, time(.empty, fallback: true))
        XCTAssertNotNil(first)
        XCTAssertGreaterThanOrEqual(first ?? 0, 5)
        XCTAssertLessThanOrEqual(first ?? 100, 85)
        XCTAssertNil(time(.empty, fallback: false))
    }

    func testServerDurationAndRandomFractionArePreferred() throws {
        let value = try payload("""
        {"titles":[],"thumbnails":[],"randomTime":0.5,"videoDuration":200}
        """)
        XCTAssertEqual(time(value), 100)
    }

    func testServerRandomFractionInOutroWrapsLikeDeArrow() throws {
        let value = try payload("""
        {"titles":[],"thumbnails":[],"randomTime":0.99,"videoDuration":100}
        """)
        XCTAssertEqual(time(value) ?? 0, 9, accuracy: 0.0001)
    }

    func testRandomFallbackDoesNotGuessDurationOrGenerateLiveFrames() {
        XCTAssertNil(DeArrowService.Payload.empty.thumbnailTime(
            videoID: "dQw4w9WgXcQ", duration: nil, randomFallback: true, isLive: false
        ))
        XCTAssertNil(DeArrowService.Payload.empty.thumbnailTime(
            videoID: "dQw4w9WgXcQ", duration: .infinity, randomFallback: true, isLive: false
        ))
        XCTAssertNil(DeArrowService.Payload.empty.thumbnailTime(
            videoID: "dQw4w9WgXcQ", duration: 100, randomFallback: true, isLive: true
        ))
    }

    func testThumbnailURLUsesOnlyReadOnlyLowPriorityParameters() throws {
        let url = try XCTUnwrap(DeArrowService.thumbnailURL(videoID: "dQw4w9WgXcQ", time: 12.5, isLive: false))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "dearrow-thumb.ajay.app")
        XCTAssertEqual(query["videoID"], "dQw4w9WgXcQ")
        XCTAssertEqual(query["time"], "12.5")
        XCTAssertEqual(query["generateNow"], "false")
        XCTAssertNil(query["userID"])
        XCTAssertNil(DeArrowService.thumbnailURL(videoID: "dQw4w9WgXcQ", time: .nan, isLive: false))
    }

    func testDisabledModelPreservesOriginalWithoutNetworking() async {
        let video = video()
        let model = DeArrowVideoViewModel()
        await model.load(video: video, replaceTitles: false, replaceThumbnails: false, randomFallback: true)
        XCTAssertEqual(model.title(for: video), video.title)
        XCTAssertNil(model.thumbnailData(for: video))
        XCTAssertFalse(model.hasReplacement(for: video))
    }

    func testOriginalChoiceIsSharedByAppearancesOfSameVideo() {
        let video = video()
        let first = DeArrowVideoViewModel()
        let second = DeArrowVideoViewModel()
        let initial = first.showsOriginal(for: video)
        first.toggleOriginal(for: video)
        XCTAssertEqual(second.showsOriginal(for: video), !initial)
        second.toggleOriginal(for: video)
        XCTAssertEqual(first.showsOriginal(for: video), initial)
    }

    func testInvalidVideoIDsNeverReachTheService() async throws {
        let result = try await DeArrowService().fetchBranding(for: video(id: "not-a-youtube-id"), includeThumbnails: true, randomFallback: true)
        XCTAssertNil(result.title)
        XCTAssertNil(result.thumbnailData)
    }

    private func payload(_ json: String) throws -> DeArrowService.Payload {
        try JSONDecoder().decode(DeArrowService.Payload.self, from: Data(json.utf8))
    }

    private func time(_ value: DeArrowService.Payload, fallback: Bool = true) -> Double? {
        value.thumbnailTime(videoID: "dQw4w9WgXcQ", duration: 100, randomFallback: fallback, isLive: false)
    }

    private func video(id: String = "dQw4w9WgXcQ") -> Video {
        Video(id: id, title: "Original title", channelID: "channel", channelName: "Channel",
              channelThumbnailURL: nil, thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
              duration: 100, viewCount: nil, publishedAt: nil, descriptionSnippet: nil,
              isLive: false, isShort: false)
    }
}
