import Foundation
import OSLog

import FreeTubeStreamKit

/// Resolves short-lived YouTube playback URLs with alexeichhorn/YouTubeKit's local extractor.
/// The extractor's hosted remote fallback is deliberately disabled: all requests and cipher
/// processing happen on the device, and signed URLs are cached in memory for at most 30 minutes.
protocol NativeStreamServicing: Sendable {
    func resolve(video: Video, quality: VideoQuality) async throws -> URL
}

final class NativeStreamService: NativeStreamServicing, @unchecked Sendable {
    private let cache: StreamURLCache
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "NativeStreamService")

    init(cache: StreamURLCache = .shared) {
        self.cache = cache
    }

    /// Returns an HLS, progressive video, or audio-only URL suitable for `AVPlayer`.
    func resolve(video: Video, quality: VideoQuality) async throws -> URL {
        let videoID = video.id
        let cacheKey = "native-\(quality.rawValue)"
        if let cached = await cache.get(videoID: videoID, formatID: cacheKey) {
            log.debug("Native stream cache hit for \(videoID, privacy: .public)")
            return cached
        }

        let startedAt = Date()
        log.info("Resolving native stream for \(videoID, privacy: .public) at \(quality.rawValue, privacy: .public) live=\(video.isLive, privacy: .public)")
        let youtube = YouTube(videoID: videoID, methods: [.local])

        do {
            // `livestreams` performs player-response work. Skip that up-front probe for ordinary
            // videos; it was adding a redundant request before every progressive resolution.
            if video.isLive,
               quality != .audioOnly,
               let hls = try await youtube.livestreams.first {
                await cache.set(videoID: videoID, formatID: cacheKey, url: hls.url)
                log.info("Resolved native HLS for \(videoID, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return hls.url
            }

            let streams = try await youtube.streams
            let selected: FreeTubeStreamKit.Stream?
            if quality == .audioOnly {
                selected = streams
                    .filterAudioOnly()
                    .filter(\.isNativelyPlayable)
                    .highestAudioBitrateStream()
            } else {
                let heightCap = quality.heightCap ?? 1080
                selected = streams
                    .filterVideoAndAudio()
                    .filter(\.isNativelyPlayable)
                    .filter { ($0.videoResolution ?? .max) <= heightCap }
                    .highestResolutionStream()
            }

            if let selected {
                await cache.set(videoID: videoID, formatID: cacheKey, url: selected.url)
                log.info("Resolved native progressive stream for \(videoID, privacy: .public) height=\(selected.videoResolution ?? 0, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return selected.url
            }

            // Some sources fail to mark a livestream in list/search metadata. Retain HLS as a
            // last native-extractor fallback, but only pay for it after progressive selection
            // produced nothing.
            if !video.isLive,
               quality != .audioOnly,
               let hls = try await youtube.livestreams.first {
                await cache.set(videoID: videoID, formatID: cacheKey, url: hls.url)
                log.info("Resolved fallback native HLS for \(videoID, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return hls.url
            }

            log.notice("Native extractor returned no playable stream for \(videoID, privacy: .public) after \(Date().timeIntervalSince(startedAt), privacy: .public)s")
            throw YouTubeServiceError.streamExtractionFailed
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.notice("Native extraction failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }
}
