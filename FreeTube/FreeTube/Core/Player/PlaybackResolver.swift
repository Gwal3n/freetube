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
/// The download pipeline remains a final compatibility fallback and explicit Download actions
/// continue to use `DownloadManager` directly.
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
            log.info("resolve: cache hit → \(local.path, privacy: .public)")
            return PlaybackCandidate(source: .localFile(local), strategy: .localFile)
        }

        if !strategies.contains(.native) {
            do {
                let result = try await nativeStreams.resolve(video: video, quality: quality)
                return PlaybackCandidate(
                    source: .direct(result.url),
                    strategy: .native,
                    storyboard: result.storyboard
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.notice("Native resolver failed for \(videoID, privacy: .public)")
            }
        }

        if !strategies.contains(.b5iIOS) {
            do {
                let info = try await videoService.fetchInfo(id: videoID)
                if let url = Self.pickStreamURL(from: info, quality: quality) {
                    log.info("resolve: produced b5i iOS candidate for \(videoID, privacy: .public)")
                    return PlaybackCandidate(source: .direct(url), strategy: .b5iIOS, storyboard: info.storyboard)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {}
        }

        if !strategies.contains(.b5iTVHTML5) {
            do {
                let info = try await videoService.fetchInfoViaTVHTML5(id: videoID)
                if let url = Self.pickStreamURL(from: info, quality: quality) {
                    log.info("resolve: produced b5i TVHTML5 candidate for \(videoID, privacy: .public)")
                    return PlaybackCandidate(source: .direct(url), strategy: .b5iTVHTML5, storyboard: info.storyboard)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {}
        }

        guard !strategies.contains(.legacyDownload) else {
            throw PlaybackResolverError.noRemainingCandidates
        }
        log.notice("Direct resolvers failed for \(videoID, privacy: .public); using legacy download fallback")
        let url = try await downloads.ensureDownloaded(video: video, quality: quality, priority: .userInitiated)
        return PlaybackCandidate(source: .localFile(url), strategy: .legacyDownload)
    }

    private static func pickStreamURL(from info: VideoInfo, quality: VideoQuality) -> URL? {
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

    var errorDescription: String? { "No playable stream candidate remained." }
}

/// Subset of `DownloadManager` the resolver depends on. Allows tests to swap a mock.
protocol DownloadManagerLike: Sendable {
    func localFile(for videoID: String) -> URL?
    func ensureDownloaded(video: Video, quality: VideoQuality, priority: DownloadPriority) async throws -> URL
}

@available(iOS 17.0, *)
extension DownloadManager: DownloadManagerLike {}

/// Subset of `DownloadManager` that older call sites depend on. Retained so the build graph stays
/// stable while we transition off `downloadTemporary` — new code should call `ensureDownloaded`.
protocol TemporaryDownloading: Sendable {
    func downloadTemporary(videoID: String, format: VideoFormat) async throws -> URL
}
