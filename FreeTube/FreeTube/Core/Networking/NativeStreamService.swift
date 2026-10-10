import Foundation
import OSLog

import FreeTubeStreamKit

/// Resolves short-lived YouTube playback URLs with alexeichhorn/YouTubeKit's local extractor.
/// The extractor's hosted remote fallback is deliberately disabled: all requests and cipher
/// processing happen on the device, and signed URLs are cached in memory for at most 30 minutes.
protocol NativeStreamServicing: Sendable {
    func resolve(video: Video, quality: VideoQuality) async throws -> NativeStreamResult
    func resolveProgressive(video: Video, quality: VideoQuality) async throws -> NativeStreamResult
}

final class NativeStreamService: NativeStreamServicing, @unchecked Sendable {
    private let cache: StreamURLCache
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "NativeStreamService")

    init(cache: StreamURLCache = .shared) {
        self.cache = cache
    }

    /// Returns an HLS, progressive video, or audio-only URL suitable for `AVPlayer`.
    func resolve(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
        try await resolve(video: video, quality: quality, progressiveOnly: false)
    }

    /// Experimental high-rate path. Never accepts an HLS playlist or downloads a file.
    func resolveProgressive(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
        guard !video.isLive else { throw YouTubeServiceError.streamExtractionFailed }
        return try await resolve(video: video, quality: quality, progressiveOnly: true)
    }

    private func resolve(video: Video, quality: VideoQuality, progressiveOnly: Bool) async throws -> NativeStreamResult {
        let videoID = video.id
        let cacheKey = "native-\(progressiveOnly ? "progressive-" : "")\(quality.rawValue)"
        if let cached = await cache.getEntry(videoID: videoID, formatID: cacheKey) {
            log.debug("Native stream cache hit for \(videoID, privacy: .public)")
            return NativeStreamResult(
                url: cached.url,
                storyboard: cached.storyboard,
                captionTracks: cached.captionTracks,
                originalAudioLanguageCode: cached.originalAudioLanguageCode,
                originalTitle: cached.originalTitle,
                mimeTypeOverride: cached.mimeTypeOverride
            )
        }

        let startedAt = Date()
        log.info("Resolving native stream for \(videoID, privacy: .public) at \(quality.rawValue, privacy: .public) live=\(video.isLive, privacy: .public) progressiveOnly=\(progressiveOnly, privacy: .public)")
        let youtube = YouTube(videoID: videoID, methods: [.local])

        do {
            // HLS first, for live and on-demand alike. `livestreams` only reads `hlsManifestUrl`
            // off the InnerTube player response, so it shares the same round-trip `streams` needs
            // but — crucially — never runs the JavaScriptCore signature/n-parameter solver.
            //
            // That solver re-parses the entire ~2.5 MB player.js once per InnerTube client (twice
            // normally, three times when no progressive format turns up), which measured at ~4s of
            // the ~5.4s native resolution. In practice its output was then discarded and this very
            // HLS URL played instead, so the whole pass was dead weight. Audio-only cannot use the
            // video-bearing master directly; select its separate audio rendition when available.
            if !progressiveOnly, quality == .audioOnly,
               let hls = try await hlsManifestURL(from: youtube, videoID: videoID) {
                do {
                    if let audio = try await NativeHLSDownloadService().preferredAudioPlaylistURL(from: hls) {
                        let storyboard = await storyboard(from: youtube, videoID: videoID)
                        let captionTracks = await sourceCaptionTracks(from: youtube, videoID: videoID)
                        let originalTitle = (try? await youtube.metadata)?.title
                        let mimeType = "application/vnd.apple.mpegurl"
                        await cache.set(
                            videoID: videoID,
                            formatID: cacheKey,
                            url: audio,
                            storyboard: storyboard,
                            captionTracks: captionTracks,
                            originalTitle: originalTitle,
                            mimeTypeOverride: mimeType
                        )
                        log.info("Resolved native audio HLS for \(videoID, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                        return NativeStreamResult(
                            url: audio,
                            storyboard: storyboard,
                            captionTracks: captionTracks,
                            originalTitle: originalTitle,
                            mimeTypeOverride: mimeType
                        )
                    }
                    log.notice("Native HLS has no separate audio rendition for \(videoID, privacy: .public); trying progressive selection")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    log.notice("Native HLS audio selection failed for \(videoID, privacy: .public); trying progressive selection")
                }
            }

            if !progressiveOnly, quality != .audioOnly,
               let hls = try await hlsManifestURL(from: youtube, videoID: videoID) {
                let storyboard = await storyboard(from: youtube, videoID: videoID)
                let captionTracks = await sourceCaptionTracks(from: youtube, videoID: videoID)
                let originalAudioLanguageCode = try? await youtube.originalAudioLanguageCode
                // The already-fetched player response carries videoDetails.title. Browsing
                // responses can instead contain a title translated for the device locale.
                let originalTitle = (try? await youtube.metadata)?.title
                await cache.set(
                    videoID: videoID,
                    formatID: cacheKey,
                    url: hls,
                    storyboard: storyboard,
                    captionTracks: captionTracks,
                    originalAudioLanguageCode: originalAudioLanguageCode,
                    originalTitle: originalTitle
                )
                log.info(
                    "Native HLS source audio language=\(originalAudioLanguageCode ?? "unknown", privacy: .public) for \(videoID, privacy: .public)"
                )
                log.info("Resolved native HLS for \(videoID, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return NativeStreamResult(
                    url: hls,
                    storyboard: storyboard,
                    captionTracks: captionTracks,
                    originalAudioLanguageCode: originalAudioLanguageCode,
                    originalTitle: originalTitle
                )
            }

            let streams = try await youtube.streams
            let selected: FreeTubeStreamKit.Stream?
            if quality == .audioOnly {
                selected = streams
                    .filterAudioOnly()
                    .filter(\.isNativelyPlayable)
                    .filter { !progressiveOnly || $0.fileExtension == .m4a || $0.fileExtension == .mp4 }
                    .highestAudioBitrateStream()
            } else {
                let heightCap = quality.heightCap ?? 1080
                selected = streams
                    .filterVideoAndAudio()
                    .filter(\.isNativelyPlayable)
                    .filter { !progressiveOnly || $0.fileExtension == .mp4 }
                    .filter { ($0.videoResolution ?? .max) <= heightCap }
                    .highestResolutionStream()
            }

            if let selected {
                // The active HLS item already supplied these fields. A high-rate source switch
                // must not pay for extra metadata requests or reset captions/chapters.
                let storyboard: VideoStoryboard? = progressiveOnly ? nil : await storyboard(from: youtube, videoID: videoID)
                let captionTracks: [VideoCaptionTrack] = progressiveOnly ? [] : await sourceCaptionTracks(from: youtube, videoID: videoID)
                let originalTitle: String? = progressiveOnly ? nil : (try? await youtube.metadata)?.title
                let mimeType: String? = progressiveOnly
                    ? (quality == .audioOnly ? "audio/mp4" : "video/mp4")
                    : (quality == .audioOnly && selected.fileExtension == .m4a ? "audio/mp4" : nil)
                await cache.set(
                    videoID: videoID, formatID: cacheKey, url: selected.url,
                    storyboard: storyboard, captionTracks: captionTracks,
                    originalTitle: originalTitle,
                    mimeTypeOverride: mimeType
                )
                log.info("Resolved native progressive stream for \(videoID, privacy: .public) height=\(selected.videoResolution ?? 0, privacy: .public) audioCodec=\(String(describing: selected.audioCodec), privacy: .public) bitrate=\(selected.bitrate ?? 0, privacy: .public) averageBitrate=\(selected.averageBitrate ?? 0, privacy: .public) container=\(selected.fileExtension.rawValue, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return NativeStreamResult(
                    url: selected.url,
                    storyboard: storyboard,
                    captionTracks: captionTracks,
                    originalTitle: originalTitle,
                    mimeTypeOverride: mimeType
                )
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

    private func sourceCaptionTracks(from youtube: YouTube, videoID: String) async -> [VideoCaptionTrack] {
        do {
            let sourceTracks = try await youtube.captionTracks
            let tracks = sourceTracks.map { track in
                VideoCaptionTrack(
                    id: track.identifier,
                    languageCode: track.languageCode,
                    languageName: track.languageName,
                    url: track.url,
                    isAutoGenerated: track.isAutoGenerated
                )
            }
            log.info("Native VISIONOS response has \(tracks.count, privacy: .public) source caption tracks for \(videoID, privacy: .public)")
            return tracks
        } catch {
            let nsError = error as NSError
            log.notice("Native captions unavailable for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            return []
        }
    }

    private func storyboard(from youtube: YouTube, videoID: String) async -> VideoStoryboard? {
        do {
            guard let storyboard = try await youtube.storyboard else {
                log.debug("Native player response contained no storyboard for \(videoID, privacy: .public)")
                return nil
            }
            let result = VideoStoryboard(
                specification: storyboard.specification,
                recommendedLevel: storyboard.recommendedLevel
            )
            log.info("Native storyboard \(result == nil ? "could not be decoded" : "resolved", privacy: .public) for \(videoID, privacy: .public)")
            return result
        } catch {
            log.notice("Native storyboard extraction failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Reads the player response's HLS manifest URL without triggering signature deciphering.
    ///
    /// Returns `nil` instead of throwing when the extractor can't produce one, so a video that
    /// genuinely has no HLS variant still falls through to progressive selection rather than
    /// failing the whole resolution. Cancellation is rethrown so a rapid video switch still
    /// unwinds immediately.
    private func hlsManifestURL(from youtube: YouTube, videoID: String) async throws -> URL? {
        do {
            return try await youtube.livestreams.first?.url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.notice("Native HLS probe found nothing for \(videoID, privacy: .public); trying progressive selection")
            return nil
        }
    }
}
