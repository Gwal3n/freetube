import Foundation

/// Owns transient download rows, retry choices, cancellation markers, and progress coalescing.
/// DownloadManager mirrors only the small public snapshot and per-video progress surface to UI.
@available(iOS 17.0, *)
@MainActor
final class DownloadTaskRegistry {
    struct RetryRequest {
        let video: Video
        let quality: VideoQuality
    }

    private var tasks: [String: DownloadTaskSnapshot] = [:]
    private var retryRequests: [String: RetryRequest] = [:]
    private var overallProgress: [String: DownloadOverallProgress] = [:]
    private var cancelledSnapshotIDs: [String] = []
    private var lastProgressPublishedAt: [String: ContinuousClock.Instant] = [:]
    private let progressPublishMinInterval: Duration = .milliseconds(200)

    var snapshots: [DownloadTaskSnapshot] {
        Array(tasks.values).sorted { $0.createdAt > $1.createdAt }
    }

    func snapshot(for id: String) -> DownloadTaskSnapshot? { tasks[id] }
    func isCancelled(_ id: String) -> Bool { cancelledSnapshotIDs.contains(id) }
    func hasSnapshot(for videoID: String) -> Bool { tasks.values.contains { $0.videoID == videoID } }

    func activeTaskIDs(for videoID: String) -> [String] {
        tasks.values.compactMap { snapshot in
            guard snapshot.videoID == videoID else { return nil }
            switch snapshot.state {
            case .queued, .downloading, .paused: return snapshot.id
            case .completed, .failed: return nil
            }
        }
    }

    func rememberRetry(id: String, video: Video, quality: VideoQuality) {
        retryRequests[id] = RetryRequest(video: video, quality: quality)
    }

    func retryableRequest(for id: String) -> (snapshot: DownloadTaskSnapshot, request: RetryRequest)? {
        guard let snapshot = tasks[id], case .failed = snapshot.state,
              let request = retryRequests[id] else { return nil }
        return (snapshot, request)
    }

    func restoreRetry(snapshot: DownloadTaskSnapshot, request: RetryRequest) {
        tasks[snapshot.id] = snapshot
        retryRequests[snapshot.id] = request
    }

    func remove(_ id: String) {
        tasks[id] = nil
        retryRequests[id] = nil
    }

    @discardableResult
    func discardFailures(for videoID: String) -> Bool {
        let ids = tasks.values.compactMap { snapshot -> String? in
            guard snapshot.videoID == videoID, case .failed = snapshot.state else { return nil }
            return snapshot.id
        }
        for id in ids { remove(id) }
        return !ids.isEmpty
    }

    func cancel(_ id: String) -> DownloadTaskSnapshot? {
        guard let snapshot = tasks[id] else { return nil }
        cancelledSnapshotIDs.append(id)
        trimCancellationMarkers()
        overallProgress[id] = nil
        remove(id)
        return snapshot
    }

    func interrupt(videoID: String) {
        let ids = tasks.values.filter { $0.videoID == videoID }.map(\.id)
        for id in ids {
            cancelledSnapshotIDs.append(id)
            overallProgress[id] = nil
            remove(id)
        }
        trimCancellationMarkers()
    }

    /// Throttle only in-flight byte updates. A new phase or terminal event resets the window.
    func shouldPublishProgress(for videoID: String) -> Bool {
        let now = ContinuousClock.now
        if let last = lastProgressPublishedAt[videoID], now - last < progressPublishMinInterval {
            return false
        }
        lastProgressPublishedAt[videoID] = now
        return true
    }

    func resetProgressThrottle(for videoID: String) {
        lastProgressPublishedAt.removeValue(forKey: videoID)
    }

    /// Returns the normalized snapshot, or nil for a cancelled task whose callback arrived late.
    func publish(_ incoming: DownloadTaskSnapshot, phase: String) -> DownloadTaskSnapshot? {
        guard !isCancelled(incoming.id) else { return nil }
        var snapshot = incoming
        if !snapshot.id.hasPrefix("fetch-"), case .downloading(let raw) = snapshot.state {
            var tracker = overallProgress[snapshot.id] ?? DownloadOverallProgress()
            let value = tracker.update(raw, phase: phase)
            overallProgress[snapshot.id] = tracker
            snapshot = DownloadTaskSnapshot(
                id: snapshot.id, videoID: snapshot.videoID, title: snapshot.title,
                state: .downloading(progress: value), createdAt: snapshot.createdAt
            )
        }
        tasks[snapshot.id] = snapshot
        if case .completed = snapshot.state {
            overallProgress[snapshot.id] = nil
            retryRequests[snapshot.id] = nil
        } else if case .failed = snapshot.state {
            overallProgress[snapshot.id] = nil
        }
        return snapshot
    }

    private func trimCancellationMarkers() {
        if cancelledSnapshotIDs.count > 256 {
            cancelledSnapshotIDs.removeFirst(cancelledSnapshotIDs.count - 256)
        }
    }
}
