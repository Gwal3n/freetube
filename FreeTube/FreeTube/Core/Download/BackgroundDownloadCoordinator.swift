import BackgroundTasks
import Foundation
import OSLog

/// Retains explicit download requests across suspension or a system termination. The system may
/// launch a processing task later; each attempt resolves fresh URLs through DownloadManager.
/// No signed YouTube URL is written into the queue or a background URL session.
@available(iOS 17.0, *)
@MainActor
final class BackgroundDownloadCoordinator {
    static let shared = BackgroundDownloadCoordinator()
    static let bgTaskIdentifier = "com.leshko.freetube.resume-downloads"

    private static let queueURL = AppDirectories.documents.deletingLastPathComponent()
        .appendingPathComponent("Library/Application Support/BackgroundDownloads.json")
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "BGDownloads")
    private var pending: [BackgroundDownloadRequest]
    private var resumeTask: Task<Void, Never>?
    private var activeVideoID: String?
    private var isRegistered = false
    private var hasScheduledRequest = false

    private init() {
        let data = try? Data(contentsOf: Self.queueURL)
        pending = data.flatMap { try? JSONDecoder().decode([BackgroundDownloadRequest].self, from: $0) } ?? []
    }

    /// Register during app launch, before any pending request is submitted.
    func registerBackgroundTasks() {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: .main
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    processingTask.setTaskCompleted(success: false)
                    return
                }
                self.handle(processingTask)
            }
        }
        if !isRegistered {
            log.error("Background processing task registration failed")
        } else if !pending.isEmpty {
            scheduleNextBackgroundTask()
        }
    }

    func record(video: Video, quality: VideoQuality) {
        guard !pending.contains(where: { $0.video.id == video.id }) else { return }
        pending.append(BackgroundDownloadRequest(video: video, quality: quality))
        save()
        scheduleNextBackgroundTask()
    }

    func complete(videoID: String) {
        guard pending.contains(where: { $0.video.id == videoID }) else { return }
        pending.removeAll { $0.video.id == videoID }
        save()
        if pending.isEmpty, hasScheduledRequest {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
            hasScheduledRequest = false
        }
    }

    func hasPendingRequest(for videoID: String) -> Bool {
        pending.contains { $0.video.id == videoID }
    }

    /// Continue interrupted requests on a normal launch too. A running download is coalesced by
    /// DownloadManager, so this does not start a duplicate transfer.
    func resumePending() {
        guard resumeTask == nil, !pending.isEmpty else { return }
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activeVideoID = nil
                self.resumeTask = nil
            }
            while !Task.isCancelled, let request = self.pending.first {
                self.activeVideoID = request.video.id
                do {
                    _ = try await DownloadManager.shared.ensureDownloaded(
                        video: request.video,
                        quality: request.quality
                    )
                } catch is CancellationError {
                    // A user cancellation removes the request; continue with the next one.
                    // An expired background attempt remains queued for a later launch.
                    if Task.isCancelled || self.pending.contains(where: { $0.video.id == request.video.id }) {
                        break
                    }
                } catch {
                    // DownloadManager retains the failed row for manual retry. Do not loop a
                    // permanently refused video in every background task.
                    self.complete(videoID: request.video.id)
                    self.log.notice("Pending download failed for \(request.video.id, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    private func save() {
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: Self.queueURL)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: Self.queueURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(pending)
            try data.write(to: Self.queueURL, options: .atomic)
        } catch {
            log.error("Could not save pending download requests: \(String(describing: error), privacy: .public)")
        }
    }

    func pauseForExpiration(videoID: String) {
        resumeTask?.cancel()
        DownloadManager.shared.interruptForBackgroundExpiration(videoID: videoID)
    }

    private func scheduleNextBackgroundTask() {
        guard isRegistered, !pending.isEmpty, !hasScheduledRequest else { return }
        let request = BGProcessingTaskRequest(identifier: Self.bgTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            hasScheduledRequest = true
        } catch {
            log.notice("Could not schedule pending downloads: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ task: BGProcessingTask) {
        hasScheduledRequest = false
        log.info("Background download processing started with \(self.pending.count, privacy: .public) pending requests")
        resumePending()
        let currentRun = resumeTask
        task.expirationHandler = { [weak self] in
            currentRun?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let videoID = self.activeVideoID {
                    self.pauseForExpiration(videoID: videoID)
                } else {
                    self.resumeTask?.cancel()
                }
            }
        }
        Task { @MainActor [weak self] in
            await currentRun?.value
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let finished = self.pending.isEmpty
            self.log.info("Background download processing ended; complete=\(finished, privacy: .public) pending=\(self.pending.count, privacy: .public)")
            task.setTaskCompleted(success: finished)
            if !finished { self.scheduleNextBackgroundTask() }
        }
    }
}
