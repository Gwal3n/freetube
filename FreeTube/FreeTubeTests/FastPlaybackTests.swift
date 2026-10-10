import XCTest
@testable import FreeTube

@available(iOS 17.0, *)
@MainActor
final class FastPlaybackTests: XCTestCase {
    func testUnsupportedOrUnpreparedItemKeepsAudibleRates() {
        for rate in [0.25, 0.75, 1, 1.35, 2] {
            XCTAssertEqual(PlaybackSpeedPresets.supportedRate(rate, canPlayFastForward: false), rate)
        }
        for rate in [2.1, 2.5, 3, 4, 5] {
            XCTAssertEqual(PlaybackSpeedPresets.supportedRate(rate, canPlayFastForward: false), 2)
        }
    }

    func testSupportedItemCanUseEntireConfiguredRange() {
        for rate in [0.25, 1.35, 2.5, 3, 4, 5] {
            XCTAssertEqual(PlaybackSpeedPresets.supportedRate(rate, canPlayFastForward: true), rate)
        }
        XCTAssertEqual(PlaybackSpeedPresets.supportedRate(10, canPlayFastForward: true), 5)
        XCTAssertEqual(PlaybackSpeedPresets.bounded(.nan), 1)
        XCTAssertEqual(PlaybackSpeedPresets.bounded(.infinity), 1)
    }

    func testFastResolverDoesNotReturnTheNormalHLSCandidate() async throws {
        let native = NativeStub()
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        let candidate = try await resolver.resolveForFastPlayback(video: video, quality: .auto)
        XCTAssertEqual(candidate.strategy, .nativeProgressive)
        XCTAssertEqual(candidate.source.url, native.progressiveURL)
        XCTAssertEqual(candidate.mimeTypeOverride, "video/mp4")
        XCTAssertEqual(native.normalCalls, 0)
        XCTAssertEqual(native.progressiveCalls, 1)
    }

    func testMissingProgressiveCandidateDoesNotSilentlyFallBackToHLS() async {
        let native = NativeStub()
        native.failProgressive = true
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        do {
            _ = try await resolver.resolveForFastPlayback(video: video, quality: .auto)
            XCTFail("An unavailable progressive stream must fail, not return HLS")
        } catch {
            XCTAssertEqual(native.normalCalls, 0)
            XCTAssertEqual(native.progressiveCalls, 1)
        }
    }

    func testNormalResolverRemainsHLSFirst() async throws {
        let native = NativeStub()
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        let candidate = try await resolver.resolve(video: video, quality: .auto)
        XCTAssertEqual(candidate.strategy, .native)
        XCTAssertEqual(candidate.source.url, native.hlsURL)
        XCTAssertEqual(native.normalCalls, 1)
        XCTAssertEqual(native.progressiveCalls, 0)
    }

    private var video: Video {
        Video(id: "testvideo01", title: "Test", channelID: "channel", channelName: "Channel",
              channelThumbnailURL: nil, thumbnailURL: nil, duration: 120, viewCount: nil,
              publishedAt: nil, descriptionSnippet: nil, isLive: false, isShort: false)
    }

    private final class NoDownloads: DownloadManagerLike {
        func localFile(for videoID: String) -> URL? { nil }
    }

    private final class NativeStub: NativeStreamServicing, @unchecked Sendable {
        let hlsURL = URL(string: "https://example.com/master.m3u8")!
        let progressiveURL = URL(string: "https://example.com/video.mp4")!
        var normalCalls = 0
        var progressiveCalls = 0
        var failProgressive = false

        func resolve(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
            normalCalls += 1
            return NativeStreamResult(url: hlsURL, storyboard: nil)
        }

        func resolveProgressive(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
            progressiveCalls += 1
            if failProgressive { throw YouTubeServiceError.streamExtractionFailed }
            return NativeStreamResult(url: progressiveURL, storyboard: nil, mimeTypeOverride: "video/mp4")
        }
    }
}
