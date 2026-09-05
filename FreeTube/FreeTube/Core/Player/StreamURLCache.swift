import Foundation
import OSLog

/// In-memory cache of resolved direct stream URLs. Per CLAUDE.md §2/§7: signed URLs are sensitive
/// and time-limited — they never touch disk. 30-minute TTL.
actor StreamURLCache {
    static let shared = StreamURLCache()

    struct Key: Hashable {
        let videoID: String
        let formatID: String
    }

    private struct Entry {
        let url: URL
        let storyboard: VideoStoryboard?
        let expiresAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let ttl: TimeInterval
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "StreamURLCache")

    init(ttl: TimeInterval = 30 * 60) {
        self.ttl = ttl
    }

    func get(videoID: String, formatID: String) -> URL? {
        getEntry(videoID: videoID, formatID: formatID)?.url
    }

    func getEntry(videoID: String, formatID: String) -> (url: URL, storyboard: VideoStoryboard?)? {
        let key = Key(videoID: videoID, formatID: formatID)
        guard let entry = entries[key] else { return nil }
        if entry.expiresAt < .now {
            entries[key] = nil
            return nil
        }
        return (entry.url, entry.storyboard)
    }

    func set(videoID: String, formatID: String, url: URL, storyboard: VideoStoryboard? = nil) {
        let key = Key(videoID: videoID, formatID: formatID)
        entries[key] = Entry(url: url, storyboard: storyboard, expiresAt: .now.addingTimeInterval(ttl))
        log.debug("Cached stream URL for \(videoID, privacy: .public)/\(formatID, privacy: .public)")
    }

    func remove(videoID: String, formatID: String) {
        entries[Key(videoID: videoID, formatID: formatID)] = nil
        log.debug("Invalidated stream URL for \(videoID, privacy: .public)/\(formatID, privacy: .public)")
    }

    func purge() {
        entries.removeAll()
    }
}
