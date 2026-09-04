import Foundation
import OSLog

/// Small in-memory cache for the expanded details and first comments page of recently played
/// videos. It never fetches continuations or replies, and it stores no signed playback URLs.
@available(iOS 17.0, *)
@MainActor
final class VideoContentPrefetchStore {
    static let shared = VideoContentPrefetchStore()

    private struct Entry {
        var details: VideoInfo? = nil
        var playbackInfo: VideoInfo? = nil
        var comments: CommentThread? = nil
    }

    private var entries: [String: Entry] = [:]
    private var detailTasks: [String: Task<VideoInfo, Error>] = [:]
    private var playbackInfoTasks: [String: Task<VideoInfo, Error>] = [:]
    private let videoService: any VideoServicing
    private let commentService: any CommentServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "ContentPrefetch")

    init(
        videoService: any VideoServicing = VideoService(),
        commentService: any CommentServicing = CommentService()
    ) {
        self.videoService = videoService
        self.commentService = commentService
    }

    func prefetch(videoID: String) async {
        do {
            let details = try await fetchDetails(videoID: videoID)
            try Task.checkCancellation()
            _ = try await fetchComments(videoID: videoID, details: details)
            log.info("Prefetched details and first comments page for \(videoID, privacy: .public)")
        } catch is CancellationError {
            log.debug("Content prefetch cancelled for \(videoID, privacy: .public)")
        } catch {
            // Prefetch is optional polish. The normal UI path remains available for retry.
            log.notice("Content prefetch failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        trimIfNeeded()
    }

    func fetchDetails(videoID: String) async throws -> VideoInfo {
        if let cached = entries[videoID]?.details { return cached }
        if let task = detailTasks[videoID] { return try await task.value }

        let service = videoService
        let task = Task { try await service.fetchMoreInfo(id: videoID) }
        detailTasks[videoID] = task
        do {
            let details = try await task.value
            var entry = entries[videoID] ?? Entry()
            entry.details = details
            entries[videoID] = entry
            detailTasks[videoID] = nil
            return details
        } catch {
            detailTasks[videoID] = nil
            throw error
        }
    }

    func fetchPlaybackInfo(videoID: String) async throws -> VideoInfo {
        if let cached = entries[videoID]?.playbackInfo { return cached }
        if let task = playbackInfoTasks[videoID] { return try await task.value }

        let service = videoService
        let task = Task {
            do {
                return try await service.fetchInfo(id: videoID)
            } catch {
                // This post-playback metadata request occasionally receives a transient
                // `Video unavailable` even while the independent native stream is playing.
                // Retry once, then try the alternate client; neither path delays playback.
                try await Task.sleep(for: .milliseconds(650))
                do {
                    return try await service.fetchInfo(id: videoID)
                } catch {
                    return try await service.fetchInfoViaTVHTML5(id: videoID)
                }
            }
        }
        playbackInfoTasks[videoID] = task
        do {
            let info = try await task.value
            var entry = entries[videoID] ?? Entry()
            entry.playbackInfo = info
            entries[videoID] = entry
            playbackInfoTasks[videoID] = nil
            return info
        } catch {
            playbackInfoTasks[videoID] = nil
            throw error
        }
    }

    func fetchComments(videoID: String) async throws -> CommentThread {
        if let cached = entries[videoID]?.comments { return cached }
        let details = try await fetchDetails(videoID: videoID)
        return try await fetchComments(videoID: videoID, details: details)
    }

    private func fetchComments(videoID: String, details: VideoInfo) async throws -> CommentThread {
        if let cached = entries[videoID]?.comments { return cached }
        let thread: CommentThread
        if details.commentsAvailability == .disabled {
            thread = CommentThread(comments: [], continuationToken: nil, availability: .disabled)
        } else if let token = details.commentsContinuationToken {
            thread = try await commentService.fetchComments(videoID: videoID, continuation: token)
        } else {
            thread = try await commentService.fetchComments(videoID: videoID, continuation: nil)
        }
        var entry = entries[videoID] ?? Entry()
        entry.comments = thread
        entries[videoID] = entry
        return thread
    }

    private func trimIfNeeded() {
        guard entries.count > 12 else { return }
        for key in Array(entries.keys.prefix(entries.count - 12)) {
            entries.removeValue(forKey: key)
        }
    }
}
