import Foundation
import OSLog

import FreeTubeStreamKit

/// Resolves short-lived YouTube playback URLs with alexeichhorn/YouTubeKit's local extractor.
/// The extractor's hosted remote fallback is deliberately disabled: all requests and cipher
/// processing happen on the device, and signed URLs are cached in memory for at most 30 minutes.
protocol NativeStreamServicing: Sendable {
    func resolve(video: Video, quality: VideoQuality) async throws -> NativeStreamResult
    func resolveProgressive(video: Video, quality: VideoQuality) async throws -> NativeStreamResult
    func resolvePaired(video: Video, quality: VideoQuality) async throws -> NativeStreamResult

    func invalidateCachedPrimaryStream(videoID: String, quality: VideoQuality) async
}

extension NativeStreamServicing {
    func invalidateCachedPrimaryStream(videoID: String, quality: VideoQuality) async {}
}

final class NativeStreamService: NativeStreamServicing, @unchecked Sendable {
    private let cache: StreamURLCache
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "NativeStreamService")

    init(cache: StreamURLCache = .shared) {
        self.cache = cache
    }

    func invalidateCachedPrimaryStream(videoID: String, quality: VideoQuality) async {
        await cache.remove(videoID: videoID, formatID: "native-\(quality.rawValue)")
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

    /// Tries separate native MP4 video and M4A audio after an HLS candidate was rejected.
    /// This is a distinct fallback so the fast HLS-first launch does not decipher streams.
    func resolvePaired(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
        guard !video.isLive, quality != .audioOnly else {
            throw YouTubeServiceError.streamExtractionFailed
        }
        let videoID = video.id
        let cacheKey = "native-paired-\(quality.rawValue)"
        if let cached = await cache.getEntry(videoID: videoID, formatID: cacheKey),
           let audioURL = cached.audioURL {
            return NativeStreamResult(
                url: cached.url, audioURL: audioURL, mediaKind: cached.mediaKind,
                storyboard: cached.storyboard,
                captionTracks: cached.captionTracks,
                originalAudioLanguageCode: cached.originalAudioLanguageCode,
                originalTitle: cached.originalTitle,
                mimeTypeOverride: cached.mimeTypeOverride
            )
        }
        let startedAt = Date()
        let youtube = YouTube(videoID: videoID, methods: [.local])
        do {
            let streams = try await youtube.streams
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
            return try await pairedResult(
                from: streams, youtube: youtube, videoID: videoID, quality: quality,
                cacheKey: cacheKey, includeMetadata: true, startedAt: startedAt
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
            log.notice("Native paired extraction failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }

    private func resolve(video: Video, quality: VideoQuality, progressiveOnly: Bool) async throws -> NativeStreamResult {
        let videoID = video.id
        let cacheKey = "native-\(progressiveOnly ? "progressive-" : "")\(quality.rawValue)"
        if let cached = await cache.getEntry(videoID: videoID, formatID: cacheKey) {
            log.debug("Native stream cache hit for \(videoID, privacy: .public)")
            return NativeStreamResult(
                url: cached.url,
                audioURL: cached.audioURL,
                mediaKind: cached.mediaKind,
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
            // HLS first, for live and on-demand alike. The fast probe reads `hlsManifestUrl`
            // from one visionOS player response; the legacy `livestreams` path follows when
            // necessary. Neither path runs the JavaScriptCore signature/n-parameter solver.
            //
            // That solver re-parses the entire ~2.5 MB player.js once per InnerTube client (twice
            // normally, three times when no progressive format turns up), which measured at ~4s of
            // the ~5.4s native resolution. In practice its output was then discarded and this very
            // HLS URL played instead, so the whole pass was dead weight. Audio-only cannot use the
            // video-bearing master directly; select its separate audio rendition when available.
            if !progressiveOnly, quality == .audioOnly,
               let hls = try await hlsManifestURL(from: youtube, videoID: videoID, isLive: video.isLive) {
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
                            mediaKind: .hls,
                            storyboard: storyboard,
                            captionTracks: captionTracks,
                            originalTitle: originalTitle,
                            mimeTypeOverride: mimeType
                        )
                        log.info("Resolved native audio HLS for \(videoID, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                        return NativeStreamResult(
                            url: audio,
                            mediaKind: .hls,
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
               let hls = try await hlsManifestURL(from: youtube, videoID: videoID, isLive: video.isLive) {
                let storyboard = await storyboard(from: youtube, videoID: videoID)
                let captionTracks = await sourceCaptionTracks(from: youtube, videoID: videoID)
                let audioLanguageStartedAt = Date()
                let originalAudioLanguageCode = try? await youtube.originalAudioLanguageCode
                log.info("Native source-audio lookup for \(videoID, privacy: .public) took \(Date().timeIntervalSince(audioLanguageStartedAt), privacy: .public)s")
                // The already-fetched player response carries videoDetails.title. Browsing
                // responses can instead contain a title translated for the device locale.
                let originalTitle = (try? await youtube.metadata)?.title
                await cache.set(
                    videoID: videoID,
                    formatID: cacheKey,
                    url: hls,
                    mediaKind: .hls,
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
                    mediaKind: .hls,
                    storyboard: storyboard,
                    captionTracks: captionTracks,
                    originalAudioLanguageCode: originalAudioLanguageCode,
                    originalTitle: originalTitle
                )
            }

            if quality == .audioOnly, !progressiveOnly {
                youtube.discardFastHLSProbe()
            }
            let streams = try await youtube.streams
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
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
                let mimeType: String? = quality == .audioOnly
                    ? ((selected.fileExtension == .m4a || selected.fileExtension == .mp4) ? "audio/mp4" : nil)
                    : (selected.fileExtension == .mp4 ? "video/mp4" : nil)
                await cache.set(
                    videoID: videoID, formatID: cacheKey, url: selected.url,
                    mediaKind: .direct,
                    storyboard: storyboard, captionTracks: captionTracks,
                    originalTitle: originalTitle,
                    mimeTypeOverride: mimeType
                )
                log.info("Resolved native progressive stream for \(videoID, privacy: .public) height=\(selected.videoResolution ?? 0, privacy: .public) audioCodec=\(String(describing: selected.audioCodec), privacy: .public) bitrate=\(selected.bitrate ?? 0, privacy: .public) averageBitrate=\(selected.averageBitrate ?? 0, privacy: .public) container=\(selected.fileExtension.rawValue, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
                return NativeStreamResult(
                    url: selected.url,
                    mediaKind: .direct,
                    storyboard: storyboard,
                    captionTracks: captionTracks,
                    originalTitle: originalTitle,
                    mimeTypeOverride: mimeType
                )
            }

            if quality != .audioOnly, !video.isLive {
                return try await pairedResult(
                    from: streams, youtube: youtube, videoID: videoID, quality: quality,
                    cacheKey: cacheKey, includeMetadata: !progressiveOnly, startedAt: startedAt
                )
            }

            log.notice("Native extractor returned no playable stream for \(videoID, privacy: .public) after \(Date().timeIntervalSince(startedAt), privacy: .public)s")
            throw YouTubeServiceError.streamExtractionFailed
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
            log.notice("Native extraction failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }

    /// Selects a native-decodable video-only/audio-only pair without downloading or muxing files.
    private func pairedResult(
        from streams: [FreeTubeStreamKit.Stream], youtube: YouTube, videoID: String,
        quality: VideoQuality, cacheKey: String, includeMetadata: Bool, startedAt: Date
    ) async throws -> NativeStreamResult {
        let heightCap = quality.heightCap ?? 1080
        let video = streams.filterVideoOnly()
            .filter { $0.isNativelyPlayable && $0.fileExtension == .mp4 }
            .filter { ($0.videoResolution ?? .max) <= heightCap }
            .sorted {
                let leftHeight = $0.videoResolution ?? 0
                let rightHeight = $1.videoResolution ?? 0
                if leftHeight != rightHeight { return leftHeight > rightHeight }
                let leftAVC: Bool
                if case .some(.avc1) = $0.videoCodec { leftAVC = true } else { leftAVC = false }
                let rightAVC: Bool
                if case .some(.avc1) = $1.videoCodec { rightAVC = true } else { rightAVC = false }
                if leftAVC != rightAVC { return leftAVC }
                return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
            }
            .first
        let audio = streams.filterAudioOnly()
            .filter { $0.isNativelyPlayable && ($0.fileExtension == .m4a || $0.fileExtension == .mp4) }
            .highestAudioBitrateStream()
        guard let video, let audio else {
            log.notice("Native extractor returned no native MP4/M4A pair for \(videoID, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
        let storyboard: VideoStoryboard? = includeMetadata ? await storyboard(from: youtube, videoID: videoID) : nil
        let captionTracks: [VideoCaptionTrack] = includeMetadata ? await sourceCaptionTracks(from: youtube, videoID: videoID) : []
        let originalAudioLanguageCode: String? = includeMetadata ? (try? await youtube.originalAudioLanguageCode) : nil
        let originalTitle: String? = includeMetadata ? (try? await youtube.metadata)?.title : nil
        await cache.set(
            videoID: videoID, formatID: cacheKey, url: video.url, audioURL: audio.url,
            mediaKind: .paired,
            storyboard: storyboard, captionTracks: captionTracks,
            originalAudioLanguageCode: originalAudioLanguageCode, originalTitle: originalTitle,
            mimeTypeOverride: "video/mp4"
        )
        // A later HLS rejection can reuse a pair already extracted by the normal path.
        if includeMetadata && cacheKey != "native-paired-\(quality.rawValue)" {
            await cache.set(
                videoID: videoID, formatID: "native-paired-\(quality.rawValue)",
                url: video.url, audioURL: audio.url, mediaKind: .paired,
                storyboard: storyboard,
                captionTracks: captionTracks,
                originalAudioLanguageCode: originalAudioLanguageCode,
                originalTitle: originalTitle, mimeTypeOverride: "video/mp4"
            )
        }
        log.info("Resolved native paired streams for \(videoID, privacy: .public) height=\(video.videoResolution ?? 0, privacy: .public) audioBitrate=\(audio.bitrate ?? 0, privacy: .public) in \(Date().timeIntervalSince(startedAt), privacy: .public)s")
        return NativeStreamResult(
            url: video.url, audioURL: audio.url, mediaKind: .paired,
            storyboard: storyboard,
            captionTracks: captionTracks,
            originalAudioLanguageCode: originalAudioLanguageCode,
            originalTitle: originalTitle, mimeTypeOverride: "video/mp4"
        )
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

    /// Tries a visitor-backed visionOS request before the other clients or full player context.
    ///
    /// Returns `nil` instead of throwing when the extractor can't produce one, so a video that
    /// genuinely has no HLS variant still falls through to progressive selection rather than
    /// failing the whole resolution. Cancellation is rethrown so a rapid video switch still
    /// unwinds immediately.
    private func hlsManifestURL(from youtube: YouTube, videoID: String, isLive: Bool) async throws -> URL? {
        let visitorStartedAt = Date()
        do {
            if let probe = try await youtube.probeVisionOSHLS() {
                log.info("Native visionOS HLS probe for \(videoID, privacy: .public) visitor=true manifest=\(probe.manifestURL != nil, privacy: .public) status=\(probe.playabilityStatus ?? "unknown", privacy: .public) idMatch=\(probe.matchesVideoID, privacy: .public) elapsed=\(Date().timeIntervalSince(visitorStartedAt), privacy: .public)s")
                if let url = probe.manifestURL { return url }
            } else {
                log.info("Native visionOS HLS probe skipped for \(videoID, privacy: .public): no visitor data elapsed=\(Date().timeIntervalSince(visitorStartedAt), privacy: .public)s")
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let nsError = error as NSError
            log.notice("Native visionOS HLS probe failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public) elapsed=\(Date().timeIntervalSince(visitorStartedAt), privacy: .public)s")
        }

        if !isLive {
            let iosStartedAt = Date()
            do {
                let probe = try await youtube.probeIOSHLS()
                log.info("Native iOS HLS probe for \(videoID, privacy: .public) manifest=\(probe.manifestURL != nil, privacy: .public) status=\(probe.playabilityStatus ?? "unknown", privacy: .public) idMatch=\(probe.matchesVideoID, privacy: .public) elapsed=\(Date().timeIntervalSince(iosStartedAt), privacy: .public)s")
                if let url = probe.manifestURL { return url }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                let nsError = error as NSError
                log.notice("Native iOS HLS probe failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public) elapsed=\(Date().timeIntervalSince(iosStartedAt), privacy: .public)s")
            }
        }

        let fallbackStartedAt = Date()
        do {
            let url = try await youtube.livestreams.first?.url
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
            log.info("Native legacy HLS fallback for \(videoID, privacy: .public) manifest=\(url != nil, privacy: .public) elapsed=\(Date().timeIntervalSince(fallbackStartedAt), privacy: .public)s")
            return url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let nsError = error as NSError
            logLegacyClientOutcomes(from: youtube, videoID: videoID)
            log.notice("Native legacy HLS fallback failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public) elapsed=\(Date().timeIntervalSince(fallbackStartedAt), privacy: .public)s")
            return nil
        }
    }

    private func logLegacyClientOutcomes(from youtube: YouTube, videoID: String) {
        for outcome in youtube.playerClientOutcomes {
            log.info("Native client=\(outcome.clientName, privacy: .public) video=\(videoID, privacy: .public) status=\(outcome.playabilityStatus ?? "unknown", privacy: .public) hls=\(outcome.hasHLSManifest, privacy: .public) idMatch=\(outcome.matchesVideoID, privacy: .public) error=\(outcome.errorDomain ?? "none", privacy: .public)/\(outcome.errorCode ?? 0, privacy: .public)")
        }
    }
}
