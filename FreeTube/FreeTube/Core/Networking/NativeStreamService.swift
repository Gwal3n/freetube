import Foundation
import OSLog

import FreeTubeStreamKit

/// Resolves short-lived YouTube playback URLs with alexeichhorn/YouTubeKit's local extractor.
/// The extractor's hosted remote fallback is deliberately disabled: all requests and cipher
/// processing happen on the device, and signed URLs are cached in memory for at most 30 minutes.
protocol NativeStreamServicing: Sendable {
    func resolve(videoID: String, quality: VideoQuality) async throws -> URL
}

final class NativeStreamService: NativeStreamServicing, @unchecked Sendable {
    private let cache: StreamURLCache
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "NativeStreamService")

    init(cache: StreamURLCache = .shared) {
        self.cache = cache
    }

    /// Returns an HLS, progressive video, or audio-only URL suitable for `AVPlayer`.
    func resolve(videoID: String, quality: VideoQuality) async throws -> URL {
        let cacheKey = "native-\(quality.rawValue)"
        if let cached = await cache.get(videoID: videoID, formatID: cacheKey) {
            log.debug("Native stream cache hit for \(videoID, privacy: .public)")
            return cached
        }

        log.info("Resolving native stream for \(videoID, privacy: .public) at \(quality.rawValue, privacy: .public)")
        let youtube = YouTube(videoID: videoID, methods: [.local])

        do {
            if quality != .audioOnly,
               let hls = try await youtube.livestreams.first {
                await cache.set(videoID: videoID, formatID: cacheKey, url: hls.url)
                log.info("Resolved native HLS for \(videoID, privacy: .public)")
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

            guard let selected else {
                log.notice("Native extractor returned no playable stream for \(videoID, privacy: .public)")
                throw YouTubeServiceError.streamExtractionFailed
            }

            await cache.set(videoID: videoID, formatID: cacheKey, url: selected.url)
            log.info("Resolved native progressive stream for \(videoID, privacy: .public) height=\(selected.videoResolution ?? 0, privacy: .public)")
            return selected.url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.notice("Native extraction failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }
}
