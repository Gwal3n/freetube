import Foundation

/// Unified row data for the "Saved on device" section. Backed by `DownloadsStore`'s
/// per-file xattr metadata, with sensible fallbacks (filename-as-title) for files that
/// have no xattr (manually dropped into the Downloads folder, or written before the xattr
/// migration).
@available(iOS 17.0, *)
struct SavedItem: Identifiable {
    let id: String
    let videoID: String
    let title: String
    let channelName: String
    let fileURL: URL
    let fileSize: Int64
    let modifiedAt: Date
    let thumbnailData: Data?
    /// Read from AVURLAsset on construction. Sync (deprecated API but fine) so we can use it as a
    /// sort key without async plumbing.
    let duration: TimeInterval?
    /// `nil` for YouTube downloads (videoID alone reconstructs the canonical YouTube URL).
    /// Set to the original pasted URL for legacy Link downloads — drives
    /// the branch between `loadLocalFile` (URL items) and the YouTube resolver.
    let originalURL: String?

    /// Convenience flag: true when this row came from the former Link downloader. Drives tap and
    /// menu behavior in `DownloadsScreen` so we don't accidentally route an Instagram
    /// download through the YouTube resolver.
    var isFromURL: Bool { originalURL != nil }

    init(from entry: DownloadEntry) {
        let fallbackID = entry.fileURL.deletingPathExtension().lastPathComponent
        self.fileURL = entry.fileURL
        self.fileSize = entry.fileSize
        // Pre-resolved during the off-main scan — no sync `AVURLAsset` read here. With a
        // large library this was the dominant source of scroll lag (the row builder ran
        // per body re-evaluation, and `.duration.seconds` is a blocking moov-atom read).
        self.duration = entry.duration
        if let m = entry.metadata {
            self.id = m.videoID
            self.videoID = m.videoID
            self.title = m.title
            self.channelName = m.channelName
            self.modifiedAt = m.downloadedAt
            self.thumbnailData = m.thumbnailData
            self.originalURL = m.originalURL
        } else {
            // Orphan: file with no metadata xattr. Surface with filename as title so the
            // user can still identify and play it.
            self.id = fallbackID
            self.videoID = fallbackID
            self.title = fallbackID
            self.channelName = ""
            self.modifiedAt = entry.modifiedAt
            self.thumbnailData = nil
            self.originalURL = nil
        }
    }
}
