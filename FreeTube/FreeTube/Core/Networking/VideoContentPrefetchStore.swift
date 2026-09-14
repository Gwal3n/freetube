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
        var comments: CommentThread? = nil
    }

    private var entries: [String: Entry] = [:]
    private var detailTasks: [String: Task<VideoInfo, Error>] = [:]
    private var commentTasks: [String: Task<CommentThread, Error>] = [:]
    private var recency: [String] = []
    private let capacity = 12
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
    }

    func fetchDetails(videoID: String) async throws -> VideoInfo {
        if let cached = entries[videoID]?.details {
            markRecentlyUsed(videoID)
            return cached
        }
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
            markRecentlyUsed(videoID)
            trimIfNeeded()
            return details
        } catch {
            detailTasks[videoID] = nil
            throw error
        }
    }

    func fetchComments(videoID: String) async throws -> CommentThread {
        if let cached = entries[videoID]?.comments {
            markRecentlyUsed(videoID)
            return cached
        }
        if let task = commentTasks[videoID] { return try await task.value }
        let details = try await fetchDetails(videoID: videoID)
        return try await fetchComments(videoID: videoID, details: details)
    }

    private func fetchComments(videoID: String, details: VideoInfo) async throws -> CommentThread {
        if let cached = entries[videoID]?.comments {
            markRecentlyUsed(videoID)
            return cached
        }
        if let task = commentTasks[videoID] { return try await task.value }

        let service = commentService
        let task = Task<CommentThread, Error> {
            if details.commentsAvailability == .disabled {
                return CommentThread(comments: [], continuationToken: nil, availability: .disabled)
            }
            if let token = details.commentsContinuationToken {
                return try await service.fetchComments(videoID: videoID, continuation: token)
            }
            return try await service.fetchComments(videoID: videoID, continuation: nil)
        }
        commentTasks[videoID] = task
        do {
            let thread = try await task.value
            var entry = entries[videoID] ?? Entry()
            entry.comments = thread
            entries[videoID] = entry
            commentTasks[videoID] = nil
            markRecentlyUsed(videoID)
            trimIfNeeded()
            return thread
        } catch {
            commentTasks[videoID] = nil
            throw error
        }
    }

    private func trimIfNeeded() {
        while entries.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private func markRecentlyUsed(_ videoID: String) {
        recency.removeAll { $0 == videoID }
        recency.append(videoID)
    }
}
