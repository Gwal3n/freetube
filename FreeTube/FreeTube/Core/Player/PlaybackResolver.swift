import Foundation
import OSLog

/// Stream-first playback resolver. An already-downloaded file remains the fastest and only offline
/// source. Otherwise alexeichhorn/YouTubeKit resolves a native direct stream, followed by the
/// existing b5i streaming endpoints. The download pipeline remains a final compatibility fallback
/// and explicit Download actions continue to use `DownloadManager` directly.
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

    func resolve(video: Video, quality: VideoQuality) async throws -> PlaybackSource {
        let videoID = video.id
        log.info("resolve(\(videoID, privacy: .public)) — checking cache")
        if let local = downloads.localFile(for: videoID) {
            log.info("resolve: cache hit → \(local.path, privacy: .public)")
            return .localFile(local)
        }
        do {
            let url = try await nativeStreams.resolve(videoID: videoID, quality: quality)
            return .direct(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.notice("Native resolver failed for \(videoID, privacy: .public); trying b5i streams")
        }

        if let url = await resolveB5IStream(videoID: videoID, quality: quality) {
            return .direct(url)
        }

        log.notice("Direct resolvers failed for \(videoID, privacy: .public); using legacy download fallback")
        let url = try await downloads.ensureDownloaded(video: video, quality: quality, priority: .userInitiated)
        return .localFile(url)
    }

    private func resolveB5IStream(videoID: String, quality: VideoQuality) async -> URL? {
        if let info = try? await videoService.fetchInfo(id: videoID) {
            if let hls = info.streamingURL { return hls }
            if let progressive = Self.pickProgressiveURL(from: info.formats, quality: quality) {
                return progressive
            }
        }
        if let info = try? await videoService.fetchInfoViaTVHTML5(id: videoID) {
            if let hls = info.streamingURL { return hls }
            return Self.pickProgressiveURL(from: info.formats, quality: quality)
        }
        return nil
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
