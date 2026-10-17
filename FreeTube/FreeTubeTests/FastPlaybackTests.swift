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

    func testRejectedHLSFallsBackToPairedStreams() async throws {
        let native = NativeStub()
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        let candidate = try await resolver.resolve(video: video, quality: .auto, excluding: [.native])
        XCTAssertEqual(candidate.strategy, .nativePaired)
        XCTAssertEqual(candidate.source, .composite(video: native.progressiveURL, audio: native.audioURL))
        XCTAssertEqual(native.normalCalls, 0)
        XCTAssertEqual(native.pairedCalls, 1)
    }

    func testNoHLSCanUsePairedStreamsOnNormalPlayback() async throws {
        let native = NativeStub()
        native.normalIsPaired = true
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        let candidate = try await resolver.resolve(video: video, quality: .auto)
        XCTAssertEqual(candidate.strategy, .nativePaired)
        XCTAssertEqual(candidate.source, .composite(video: native.progressiveURL, audio: native.audioURL))
        XCTAssertEqual(native.pairedCalls, 0)
    }

    func testFastResolverAcceptsSeparateTracksWithoutHLS() async throws {
        let native = NativeStub()
        native.progressiveIsPaired = true
        let resolver = PlaybackResolver(downloads: NoDownloads(), nativeStreams: native)
        let candidate = try await resolver.resolveForFastPlayback(video: video, quality: .auto)
        XCTAssertEqual(candidate.strategy, .nativePaired)
        XCTAssertEqual(candidate.source, .composite(video: native.progressiveURL, audio: native.audioURL))
        XCTAssertEqual(native.normalCalls, 0)
        XCTAssertEqual(native.progressiveCalls, 1)
    }

    func testPairedCacheRetainsBothURLsInMemory() async {
        let cache = StreamURLCache()
        let videoURL = URL(string: "https://example.com/video.mp4")!
        let audioURL = URL(string: "https://example.com/audio.m4a")!
        await cache.set(videoID: "testvideo01", formatID: "native-paired-auto",
                        url: videoURL, audioURL: audioURL, mediaKind: .paired)
        let entry = await cache.getEntry(videoID: "testvideo01", formatID: "native-paired-auto")
        XCTAssertEqual(entry?.url, videoURL)
        XCTAssertEqual(entry?.audioURL, audioURL)
        XCTAssertEqual(entry?.mediaKind, .paired)
        XCTAssertEqual(
            NativeStreamResult(url: videoURL, audioURL: audioURL, storyboard: nil).mediaKind,
            .paired
        )
        await cache.purge()
        let purged = await cache.getEntry(videoID: "testvideo01", formatID: "native-paired-auto")
        XCTAssertNil(purged)
    }

    func testStreamCacheEvictsLeastRecentlyUsedResolution() async {
        let cache = StreamURLCache(capacity: 2)
        let first = URL(string: "https://example.com/first.m3u8")!
        let second = URL(string: "https://example.com/second.m3u8")!
        let third = URL(string: "https://example.com/third.m3u8")!

        await cache.set(videoID: "first", formatID: "native", url: first)
        await cache.set(videoID: "second", formatID: "native", url: second)
        let touchedFirst = await cache.get(videoID: "first", formatID: "native")
        XCTAssertEqual(touchedFirst, first)
        await cache.set(videoID: "third", formatID: "native", url: third)

        let evictedSecond = await cache.get(videoID: "second", formatID: "native")
        let retainedFirst = await cache.get(videoID: "first", formatID: "native")
        let retainedThird = await cache.get(videoID: "third", formatID: "native")
        XCTAssertNil(evictedSecond)
        XCTAssertEqual(retainedFirst, first)
        XCTAssertEqual(retainedThird, third)
    }

    func testStreamCacheDoesNotReturnImmediatelyExpiredURL() async {
        let cache = StreamURLCache(ttl: 0)
        await cache.set(videoID: "expired", formatID: "native", url: URL(string: "https://example.com/expired")!)
        let expired = await cache.get(videoID: "expired", formatID: "native")
        XCTAssertNil(expired)
    }

    func testRejectedNativeURLDoesNotEvictPairedFallback() async {
        let cache = StreamURLCache()
        let videoID = "testvideo01"
        let hlsURL = URL(string: "https://example.com/broken.m3u8")!
        let videoURL = URL(string: "https://example.com/video.mp4")!
        let audioURL = URL(string: "https://example.com/audio.m4a")!
        await cache.set(videoID: videoID, formatID: "native-auto", url: hlsURL, mediaKind: .hls)
        await cache.set(
            videoID: videoID, formatID: "native-paired-auto",
            url: videoURL, audioURL: audioURL, mediaKind: .paired
        )

        let resolver = PlaybackResolver(
            downloads: NoDownloads(), nativeStreams: NativeStreamService(cache: cache)
        )
        await resolver.invalidateRejectedCandidate(
            PlaybackCandidate(source: .direct(hlsURL), strategy: .native),
            videoID: videoID,
            quality: .auto
        )

        let rejected = await cache.getEntry(videoID: videoID, formatID: "native-auto")
        let fallback = await cache.getEntry(videoID: videoID, formatID: "native-paired-auto")
        XCTAssertNil(rejected)
        XCTAssertEqual(fallback?.url, videoURL)
        XCTAssertEqual(fallback?.audioURL, audioURL)
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
        let audioURL = URL(string: "https://example.com/audio.m4a")!
        var normalCalls = 0
        var progressiveCalls = 0
        var pairedCalls = 0
        var failProgressive = false
        var progressiveIsPaired = false
        var normalIsPaired = false

        func resolve(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
            normalCalls += 1
            if normalIsPaired {
                return NativeStreamResult(url: progressiveURL, audioURL: audioURL, storyboard: nil)
            }
            return NativeStreamResult(url: hlsURL, storyboard: nil)
        }

        func resolveProgressive(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
            progressiveCalls += 1
            if failProgressive { throw YouTubeServiceError.streamExtractionFailed }
            return NativeStreamResult(
                url: progressiveURL, audioURL: progressiveIsPaired ? audioURL : nil,
                storyboard: nil, mimeTypeOverride: "video/mp4"
            )
        }

        func resolvePaired(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
            pairedCalls += 1
            return NativeStreamResult(
                url: progressiveURL, audioURL: audioURL,
                storyboard: nil, mimeTypeOverride: "video/mp4"
            )
        }
    }
}
