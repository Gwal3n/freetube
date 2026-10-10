import AVFoundation
import Foundation
import OSLog

/// Stream-first playback resolver. An already-downloaded file remains the fastest and only offline
/// source. Otherwise the native extractor runs first — it now returns the InnerTube HLS manifest
/// without any signature deciphering, which makes it both the fastest and the most reliable
/// candidate. The b5i streaming endpoints follow as a safety net: for ordinary VOD their
/// `VideoInfosResponse` reports no HLS URL and its formats carry metadata only (upstream documents
/// that real URLs need `VideoInfosWithDownloadFormatsResponse.deciphersURLs(player:)`), so running
/// them first was spending ~1.5s per play on candidates that could not be produced. They still earn
/// their place behind the native resolver for the cases where it comes back empty.
/// Playback never starts a download as a side effect. Explicit Download actions continue to use
/// `DownloadManager` directly.
final class PlaybackResolver: PlaybackResolving {
    private let downloads: DownloadManagerLike
    private let nativeStreams: any NativeStreamServicing
    private let videoService: any VideoServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlaybackResolver")

    init(
        downloads: DownloadManagerLike = DownloadManager.shared,
        nativeStreams: any NativeStreamServicing = NativeStreamService(),
        videoService: any VideoServicing = VideoService()
    ) {
        self.downloads = downloads
        self.nativeStreams = nativeStreams
        self.videoService = videoService
    }

    func resolve(
        video: Video,
        quality: VideoQuality,
        excluding strategies: Set<PlaybackStrategy> = []
    ) async throws -> PlaybackCandidate {
        let videoID = video.id
        log.info("resolve(\(videoID, privacy: .public)) excluded=\(strategies.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
        if !strategies.contains(.localFile), let local = downloads.localFile(for: videoID) {
            // Downloads use `<videoID>.mp4` for both video and audio-only files. The name alone
            // cannot prove this file satisfies a request to show video. Inspect only local files;
            // a mismatch falls through to normal stream resolution without deleting the download.
            if quality == .audioOnly {
                log.info("resolve: cache hit → \(local.path, privacy: .public)")
                return PlaybackCandidate(source: .localFile(local), strategy: .localFile)
            }
            let videoTracks = try? await AVURLAsset(url: local).loadTracks(withMediaType: .video)
            if videoTracks?.isEmpty == false {
                log.info("resolve: cache hit → \(local.path, privacy: .public)")
                return PlaybackCandidate(source: .localFile(local), strategy: .localFile)
            }
            log.info("resolve: audio-only local file cannot satisfy video playback for \(videoID, privacy: .public)")
        }

        if !strategies.contains(.native) {
            do {
                let result = try await nativeStreams.resolve(video: video, quality: quality)
                let strategy: PlaybackStrategy = result.audioURL == nil ? .native : .nativePaired
                if !strategies.contains(strategy) {
                    return Self.nativeCandidate(result, strategy: strategy)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("Native resolver failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }

        // If a native HLS item was rejected by AVPlayer, try the separate MP4/M4A tracks
        // before the b5i endpoints. This work is never part of a successful HLS launch.
        if strategies.contains(.native), !strategies.contains(.nativePaired),
           !video.isLive, quality != .audioOnly {
            do {
                let result = try await nativeStreams.resolvePaired(video: video, quality: quality)
                return Self.nativeCandidate(result, strategy: .nativePaired)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("Native paired fallback unavailable for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }

        if !strategies.contains(.b5iIOS) {
            do {
                let info = try await videoService.fetchInfo(id: videoID)
                if let url = Self.pickStreamURL(from: info, quality: quality) {
                    log.info("resolve: produced b5i iOS candidate for \(videoID, privacy: .public)")
                    return PlaybackCandidate(
                        source: .direct(url), strategy: .b5iIOS,
                        storyboard: info.storyboard, originalTitle: info.video.title
                    )
                }
                log.notice("b5i iOS returned no playable URL for \(videoID, privacy: .public) hls=\(info.streamingURL != nil, privacy: .public) formats=\(info.formats.count, privacy: .public)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("b5i iOS failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }

        if !strategies.contains(.b5iTVHTML5) {
            do {
                let info = try await videoService.fetchInfoViaTVHTML5(id: videoID)
                if let url = Self.pickStreamURL(from: info, quality: quality) {
                    log.info("resolve: produced b5i TVHTML5 candidate for \(videoID, privacy: .public)")
                    return PlaybackCandidate(
                        source: .direct(url), strategy: .b5iTVHTML5,
                        storyboard: info.storyboard, originalTitle: info.video.title
                    )
                }
                log.notice("b5i TVHTML5 returned no playable URL for \(videoID, privacy: .public) hls=\(info.streamingURL != nil, privacy: .public) formats=\(info.formats.count, privacy: .public)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("b5i TVHTML5 failed for \(videoID, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }

        log.notice("No playable stream remained for \(videoID, privacy: .public)")
        throw PlaybackResolverError.noRemainingCandidates
    }

    /// Separate from normal resolution so a high-rate request cannot silently return the same
    /// HLS stream that already reported `canPlayFastForward == false`.
    func resolveForFastPlayback(video: Video, quality: VideoQuality) async throws -> PlaybackCandidate {
        log.info("Resolving progressive fast-playback candidate for \(video.id, privacy: .public)")
        let result = try await nativeStreams.resolveProgressive(video: video, quality: quality)
        return Self.nativeCandidate(result, strategy: result.audioURL == nil ? .nativeProgressive : .nativePaired)
    }

    private static func nativeCandidate(_ result: NativeStreamResult, strategy: PlaybackStrategy) -> PlaybackCandidate {
        let source: PlaybackSource
        if let audioURL = result.audioURL {
            source = .composite(video: result.url, audio: audioURL)
        } else {
            source = .direct(result.url)
        }
        return PlaybackCandidate(
            source: source, strategy: strategy, storyboard: result.storyboard,
            captionTracks: result.captionTracks,
            originalAudioLanguageCode: result.originalAudioLanguageCode,
            originalTitle: result.originalTitle, mimeTypeOverride: result.mimeTypeOverride
        )
    }

    private static func pickStreamURL(from info: VideoInfo, quality: VideoQuality) -> URL? {
        if quality == .audioOnly {
            return info.formats
                .filter { $0.isAudioOnly && $0.url != nil }
                .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }?
                .url
        }
        if let hls = info.streamingURL { return hls }
        return Self.pickProgressiveURL(from: info.formats, quality: quality)
    }

    private static func pickProgressiveURL(from formats: [VideoFormat], quality: VideoQuality) -> URL? {
        let heightCap = quality.heightCap ?? 1080
        return formats
            .filter { $0.containsBothTracks && $0.url != nil }
            .filter { ($0.height ?? .max) <= heightCap }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
            .first?
            .url
    }
}

private enum PlaybackResolverError: LocalizedError {
    case noRemainingCandidates

    var errorDescription: String? { "This video couldn't be played because no stream was available." }
}

/// Local-file lookup used by playback. Allows tests to swap a mock without initiating downloads.
protocol DownloadManagerLike: Sendable {
    func localFile(for videoID: String) -> URL?
}

@available(iOS 17.0, *)
extension DownloadManager: DownloadManagerLike {}
