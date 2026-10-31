import Foundation
import OSLog

/// Attaches portable metadata and optional artwork after a media file passes validation.
@available(iOS 17.0, *)
@MainActor
final class DownloadMetadataWriter {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")

    func persist(video: Video, fileURL: URL) async {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let thumbnail = await thumbnailData(url: video.thumbnailURL)
        let thumbnailSize = thumbnail.map { "\($0.count)B" } ?? "nil"
        log.debug("persistDownloaded(\(video.id, privacy: .public)) thumb=\(thumbnailSize, privacy: .public) size=\(size, privacy: .public)")
        // Xattr metadata travels with the file; DownloadsStore compresses the artwork and
        // notifies the Downloads tab after writing it.
        await DownloadsStore.shared.write(
            videoID: video.id,
            title: video.title,
            channelName: video.channelName,
            formatID: "ytdl",
            originalURL: nil,
            rawThumbnail: thumbnail,
            at: fileURL
        )
        log.info("persistDownloaded(\(video.id, privacy: .public)) wrote xattr size=\(size, privacy: .public) bytes")
        // Caption sidecars are optional and never hold up a completed media download.
        Task { await OfflineCaptionStore.shared.downloadAvailableTracks(for: video.id) }
    }

    private func thumbnailData(url: URL?) async -> Data? {
        guard let url else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}
