import Foundation
import OSLog

/// Selects usable download sources without owning transfer state or progress reporting.
@available(iOS 17.0, *)
@MainActor
final class DownloadSourceSelector {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")

    /// Prefer TVHTML5's direct URLs, then use YouTubeKit's player-JS format extraction when
    /// cipher-protected URLs leave the first response without usable formats.
    func fallbackFormats(videoID: String) async -> [VideoFormat] {
        let service = VideoService()
        do {
            let info = try await service.fetchInfoViaTVHTML5(id: videoID)
            let usable = info.formats.filter { $0.url != nil }
            if !usable.isEmpty {
                log.info("[fallback] TVHTML5 returned \(info.formats.count, privacy: .public) formats, \(usable.count, privacy: .public) with URLs")
                return usable
            }
            log.notice("[fallback] TVHTML5 returned \(info.formats.count, privacy: .public) formats but 0 with direct URLs (cipher-protected); trying player.js scrape")
        } catch {
            log.notice("[fallback] TVHTML5 fetch failed: \(String(describing: error), privacy: .public); trying player.js scrape")
        }
        do {
            let result = try await service.fetchInfoWithFormats(id: videoID)
            let usable = result.formats.filter { $0.url != nil }
            log.info("[fallback] fetchInfoWithFormats returned \(result.formats.count, privacy: .public) formats, \(usable.count, privacy: .public) with URLs")
            return usable
        } catch {
            log.error("[fallback] fetchInfoWithFormats failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Give explicit 1440p/2160p downloads a chance at paired streams before falling back to
    /// the usual HLS-first resolver. HLS can otherwise hide an available higher resolution.
    func nativeSource(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
        let service = NativeStreamService()
        if !video.isLive, (quality.heightCap ?? 0) > 1080 {
            do {
                let source = try await service.resolvePaired(video: video, quality: quality)
                log.info("native-download[\(video.id, privacy: .public)] selected high-resolution paired source")
                return source
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("native-download[\(video.id, privacy: .public)] high-resolution pair unavailable; trying HLS: \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }
        return try await service.resolve(video: video, quality: quality)
    }
}
