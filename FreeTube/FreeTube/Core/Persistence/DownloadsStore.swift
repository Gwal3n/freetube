import AVFoundation
import Foundation
import Observation
import OSLog
import UIKit

/// File-system + xattr download index for `Documents` media. Refreshes on app mutations.
@available(iOS 17.0, *)
@Observable
@MainActor
final class DownloadsStore {
    static let shared = DownloadsStore()

    nonisolated static let didChange = Notification.Name("com.leshko.freetube.downloadsDidChange")

    /// xattr key holding the serialized `DownloadMetadata` for a file. App-prefixed so
    /// other tools (Files.app, Finder) don't show it as plain text.
    nonisolated static let metadataXattrKey = "com.leshko.freetube.downloadMetadata"

    /// JPEG compression target. ~10 KB at 200×112 for typical YouTube thumbnails — fits
    /// comfortably in an xattr value with room to spare.
    nonisolated static let thumbnailMaxWidth: CGFloat = 200
    nonisolated static let thumbnailJpegQuality: CGFloat = 0.55

    /// Current snapshot. `@Observable` re-emits on assignment. Always assigned on the main
    /// actor at the end of a background scan — views observe via SwiftUI's standard
    /// observation tracking.
    private(set) var entries: [DownloadEntry] = []
    /// True while a background scan is in flight. `SettingsScreen` and others can read this
    /// to show a spinner next to the cache-size label on first launch.
    private(set) var isScanning: Bool = false

    @ObservationIgnored private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadsStore")
    @ObservationIgnored private var notificationObserver: NSObjectProtocol?
    /// Most recent in-flight scan. Cancelled before starting a new one so back-to-back
    /// `didChange` notifications can't pile up several stale scans whose late completions
    /// would overwrite each other in arbitrary order.
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    private init() {
        Self.migrateLegacyDownloadsFolder()
        notificationObserver = NotificationCenter.default.addObserver(
            forName: Self.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Moves legacy `Documents/Downloads/` files up to Documents root (idempotent, sync on init).
    private nonisolated static func migrateLegacyDownloadsFolder() {
        let docs = downloadsDirectory()
        let legacy = docs.appendingPathComponent("Downloads", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacy.path, isDirectory: &isDir), isDir.boolValue else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            let dest = docs.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: url, to: dest)
        }
        try? FileManager.default.removeItem(at: legacy)
    }

    deinit {
        scanTask?.cancel()
        if let token = notificationObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Read

    /// Scans Documents off-main; cancels any in-flight scan so only the latest result lands.
    func refresh() {
        scanTask?.cancel()
        isScanning = true
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let scanned = Self.scanDirectory()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.entries = scanned
                self.isScanning = false
                self.log.debug("refresh: \(scanned.count, privacy: .public) entries from \(Self.downloadsDirectory().path, privacy: .public)")
            }
        }
    }

    /// Sorted filesystem scan + xattr decode (newest first).
    private nonisolated static func scanDirectory() -> [DownloadEntry] {
        let dir = downloadsDirectory()
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let mediaURLs = fileURLs.filter { ["mp4", "m4a", "mp3", "webm", "opus"].contains($0.pathExtension.lowercased()) }
        return mediaURLs.compactMap(makeEntry(from:)).sorted { $0.sortDate > $1.sortDate }
    }

    func thumbnail(forVideoID videoID: String) -> Data? {
        entries.first { $0.metadata?.videoID == videoID }?.metadata?.thumbnailData
    }

    func metadata(at fileURL: URL) -> DownloadMetadata? {
        if let cached = entries.first(where: { $0.fileURL == fileURL }) {
            return cached.metadata
        }
        return Self.readMetadata(at: fileURL)
    }

    // MARK: - Write

    /// Writes metadata xattr off-main (thumbnail compress + duration probe), then posts `didChange`.
    func write(
        videoID: String,
        title: String,
        channelName: String,
        formatID: String,
        originalURL: String?,
        rawThumbnail: Data?,
        at fileURL: URL
    ) async {
        // Capture all inputs by value (they're all Sendable types) so the detached task
        // doesn't pin any actor-isolated reference.
        await Task.detached(priority: .utility) {
            let thumb = rawThumbnail.flatMap(Self.compressedThumbnail(_:))
            let duration = Self.readDuration(at: fileURL)
            let metadata = DownloadMetadata(
                videoID: videoID,
                title: title,
                channelName: channelName,
                formatID: formatID,
                downloadedAt: .now,
                originalURL: originalURL,
                thumbnailData: thumb,
                duration: duration
            )
            do {
                let blob = try PropertyListEncoder().encode(metadata)
                try FileXattr.write(blob, key: Self.metadataXattrKey, at: fileURL)
            } catch {
                // Logging happens on main below — only if needed.
            }
            await MainActor.run {
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }.value
    }

    /// Delete the underlying mp4 (the xattr goes with it). Posts a change notification so
    /// other observers (`DownloadsScreen`) refresh.
    func delete(at fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
            if fileURL.pathExtension.lowercased() == "mp4" {
                let videoID = fileURL.deletingPathExtension().lastPathComponent
                Task { await OfflineCaptionStore.shared.delete(for: videoID) }
            }
            log.info("deleted \(fileURL.lastPathComponent, privacy: .public)")
        } catch {
            log.error("delete failed for \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Delete a playlist's media as one batch, off the main actor. Missing files are already
    /// removed; any genuine failures are reported so the playlist record can be retained for
    /// another attempt. A single notification avoids a full directory scan per video.
    func deleteFiles(at urls: [URL]) async -> Bool {
        let failed = await Task.detached(priority: .utility) {
            var failures: [String] = []
            for url in urls {
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            return failures
        }.value
        for url in urls where !FileManager.default.fileExists(atPath: url.path) && url.pathExtension.lowercased() == "mp4" {
            await OfflineCaptionStore.shared.delete(for: url.deletingPathExtension().lastPathComponent)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        if !failed.isEmpty {
            log.error("playlist deletion failed for \(failed.joined(separator: ", "), privacy: .public)")
        }
        return failed.isEmpty
    }

    // MARK: - Internals

    /// Documents root (Files app sharing); SwiftData lives under Application Support.
    nonisolated static func downloadsDirectory() -> URL {
        AppDirectories.documents
    }

    /// Stat + xattr for one file; duration from xattr or AVURLAsset. Nil only if the file vanished.
    private nonisolated static func makeEntry(from url: URL) -> DownloadEntry? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
        let metadata = readMetadata(at: url)
        let duration = metadata?.duration ?? readDuration(at: url)
        return DownloadEntry(
            fileURL: url,
            metadata: metadata,
            fileSize: size,
            modifiedAt: mtime,
            duration: duration
        )
    }

    private nonisolated static func readMetadata(at url: URL) -> DownloadMetadata? {
        guard let blob = FileXattr.read(key: metadataXattrKey, at: url) else { return nil }
        return try? PropertyListDecoder().decode(DownloadMetadata.self, from: blob)
    }

    /// Local-file duration via AVURLAsset; call only off-main.
    nonisolated static func readDuration(at url: URL) -> TimeInterval? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        let seconds = asset.duration.seconds
        return (seconds.isFinite && seconds > 0) ? seconds : nil
    }

    private nonisolated static func compressedThumbnail(_ raw: Data) -> Data? {
        guard let image = UIImage(data: raw) else { return nil }
        let maxW = thumbnailMaxWidth
        let scale = min(1, maxW / max(image.size.width, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: thumbnailJpegQuality)
    }
}

/// Filesystem scan row. Missing metadata → orphan (filename as title).
@available(iOS 17.0, *)
struct DownloadEntry: Identifiable, Sendable {
    let fileURL: URL
    let metadata: DownloadMetadata?
    let fileSize: Int64
    let modifiedAt: Date
    /// Pre-resolved off-main; never probe AVURLAsset from a SwiftUI body.
    let duration: TimeInterval?

    var id: String { fileURL.path }
    var videoID: String { metadata?.videoID ?? fileURL.deletingPathExtension().lastPathComponent }

    /// Date used for the newest-first sort. Prefer metadata when available (matches the
    /// previous SwiftData behavior), fall back to file modification time for orphans.
    var sortDate: Date { metadata?.downloadedAt ?? modifiedAt }
}
