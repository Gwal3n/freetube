import Foundation
import OSLog
import SwiftData

/// Explicit downloads, local cache lookup, and observable transfer progress.
@available(iOS 17.0, *)
@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var activeTasks: [DownloadTaskSnapshot] = []
    private(set) var progressByVideoID: [String: Double] = [:]
    /// Phase label such as "video", "audio", or "muxing".
    private(set) var phaseByVideoID: [String: String] = [:]

    /// Retains retry and progress internals without making every byte callback observable.
    @ObservationIgnored private let taskRegistry = DownloadTaskRegistry()

    /// Coalesces concurrent `ensureDownloaded` calls for the same video so we don't start two
    /// downloads in parallel for the same id (which would race on the destination path).
    private var inflight: [String: Task<URL, Error>] = [:]
    @ObservationIgnored private let mediaFinalizer = DownloadMediaFinalizer()
    @ObservationIgnored private let metadataWriter = DownloadMetadataWriter()
    @ObservationIgnored private let sourceSelector = DownloadSourceSelector()
    @ObservationIgnored private let streamTransfer = DownloadStreamTransfer()
    private let preferences = UserPreferences()
    @ObservationIgnored private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")
    @ObservationIgnored private let networkGate: DownloadNetworkGate

    private init() {
        networkGate = DownloadNetworkGate()
    }

    // MARK: - Public surface

    /// Returns the local file URL for a downloaded video, or nil if it isn't on disk.
    /// Pure filesystem check — no I/O beyond `fileExists`. Called from SwiftUI bodies, so
    /// no logging here.
    func localFile(for videoID: String) -> URL? {
        let url = Self.fileURL(for: videoID)
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= DownloadMediaFinalizer.minimumFileSize else {
            return nil
        }
        return url
    }

    /// Either returns the existing local file URL, or downloads the video and returns
    /// the freshly-written path. Coalesces parallel callers for the same `videoID`.
    func ensureDownloaded(video: Video, quality: VideoQuality) async throws -> URL {
        try Task.checkCancellation()
        log.info("ensureDownloaded(\(video.id, privacy: .public)) — title=\"\(video.title, privacy: .public)\" quality=\(quality.rawValue, privacy: .public)")
        // A direct stream may already be writing the destination. Join that transfer before
        // checking the file size, otherwise a partial MP4 can look like a completed cache hit.
        if let inflightTask = inflight[video.id] {
            if inflightTask.isCancelled {
                _ = try? await inflightTask.value
            } else {
                log.info("ensureDownloaded(\(video.id, privacy: .public)): joining inflight task")
                return try await inflightTask.value
            }
        }
        if let existing = localFile(for: video.id) {
            if BackgroundDownloadCoordinator.shared.hasPendingRequest(for: video.id) {
                // A process can die after writing enough bytes to pass localFile's size check
                // but before validation. Only an interrupted request needs this extra probe.
                do {
                    try await mediaFinalizer.validateFile(at: existing, quality: quality, videoID: video.id)
                    try Task.checkCancellation()
                    if DownloadsStore.shared.metadata(at: existing) == nil {
                        await metadataWriter.persist(video: video, fileURL: existing)
                    }
                    BackgroundDownloadCoordinator.shared.complete(videoID: video.id)
                    return existing
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    try? FileManager.default.removeItem(at: existing)
                }
            } else {
                log.info("ensureDownloaded(\(video.id, privacy: .public)): cache hit")
                Task { await OfflineCaptionStore.shared.downloadAvailableTracks(for: video.id) }
                return existing
            }
        }

        BackgroundDownloadCoordinator.shared.record(video: video, quality: quality)
        if taskRegistry.discardFailures(for: video.id) { publishSnapshots() }

        log.info("ensureDownloaded(\(video.id, privacy: .public)): checking network gate (allowCellular=\(self.preferences.allowCellularDownloads, privacy: .public))")
        do {
            try networkGate.requireAllowedNetwork(allowCellularDownloads: preferences.allowCellularDownloads)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            BackgroundDownloadCoordinator.shared.complete(videoID: video.id)
            let snapshotID = UUID().uuidString
            taskRegistry.rememberRetry(id: snapshotID, video: video, quality: quality)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID,
                videoID: video.id,
                title: video.title,
                state: .failed(error.localizedDescription),
                createdAt: .now
            ))
            throw error
        }
        try Task.checkCancellation()
        log.info("ensureDownloaded(\(video.id, privacy: .public)): network gate passed, spawning download task")

        let lease = DownloadExecutionLease {
            BackgroundDownloadCoordinator.shared.pauseForExpiration(videoID: video.id)
        }
        let task = Task<URL, Error> { @MainActor [weak self] in
            guard let self else {
                lease.end()
                throw YouTubeServiceError.unknown(NSError(domain: "DownloadManager", code: -1))
            }
            defer {
                lease.end()
                self.inflight[video.id] = nil
            }
            do {
                let url = try await self.runDownload(video: video, quality: quality)
                BackgroundDownloadCoordinator.shared.complete(videoID: video.id)
                return url
            } catch {
                if !Task.isCancelled {
                    BackgroundDownloadCoordinator.shared.complete(videoID: video.id)
                }
                throw error
            }
        }
        inflight[video.id] = task
        return try await task.value
    }

    /// Deletes the local file and SwiftData row; `context` retained for call-site compatibility.
    func deleteDownloaded(videoID: String, context: ModelContext) {
        let url = Self.fileURL(for: videoID)
        DownloadsStore.shared.delete(at: url)
        log.info("Deleted download \(videoID, privacy: .public)")
    }

    func cancel(taskID: String) {
        guard let snapshot = taskRegistry.cancel(taskID) else { return }
        BackgroundDownloadCoordinator.shared.complete(videoID: snapshot.videoID)
        progressByVideoID[snapshot.videoID] = nil
        phaseByVideoID[snapshot.videoID] = nil
        publishSnapshots()
        if let task = inflight[snapshot.videoID] {
            task.cancel()
        }
    }

    /// Cancel by video even before the first transfer snapshot appears (for example while the
    /// network gate is running). A user cancellation must also clear the persisted request.
    func cancel(videoID: String) {
        BackgroundDownloadCoordinator.shared.complete(videoID: videoID)
        let runningIDs = taskRegistry.activeTaskIDs(for: videoID)
        for id in runningIDs { cancel(taskID: id) }
        inflight[videoID]?.cancel()
    }

    /// Stop active work when iOS expires its background runtime. The persisted request remains
    /// available for a fresh attempt with newly resolved stream URLs.
    func interruptForBackgroundExpiration(videoID: String) {
        inflight[videoID]?.cancel()
        taskRegistry.interrupt(videoID: videoID)
        progressByVideoID[videoID] = nil
        phaseByVideoID[videoID] = nil
        publishSnapshots()
    }

    /// Starts a fresh attempt for a failed transfer using its original video and quality.
    /// This is a retry from the beginning, not a claim that HLS can resume partial bytes.
    func retry(taskID: String) async throws {
        guard let retry = taskRegistry.retryableRequest(for: taskID) else {
            throw NSError(
                domain: "com.leshko.freetube.download",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This download can no longer be retried. Start it again from the video."]
            )
        }
        let snapshot = retry.snapshot
        let request = retry.request

        // A failure snapshot can be published just before the previous task's defer clears
        // `inflight`. Await it so ensureDownloaded does not join that failed attempt.
        if let previous = inflight[snapshot.videoID] {
            _ = try? await previous.value
        }
        taskRegistry.remove(taskID)
        publishSnapshots()
        do {
            _ = try await ensureDownloaded(
                video: request.video,
                quality: request.quality
            )
        } catch {
            // A network gate can fail before the new attempt creates a snapshot. Restore
            // the retryable row in that case; actual transfer failures publish their own row.
            if !taskRegistry.hasSnapshot(for: snapshot.videoID) {
                taskRegistry.restoreRetry(snapshot: snapshot, request: request)
                publishSnapshots()
            }
            throw error
        }
    }

    // MARK: - Download execution

    private func runDownload(video: Video, quality: VideoQuality) async throws -> URL {
        let startedAt = Date()
        log.info("download[\(video.id, privacy: .public)] start quality=\(quality.rawValue, privacy: .public)")
        let snapshotID = UUID().uuidString
        taskRegistry.rememberRetry(id: snapshotID, video: video, quality: quality)
        log.debug("download[\(video.id, privacy: .public)] snapshotID=\(snapshotID, privacy: .public) → state=queued")
        publish(snapshot: DownloadTaskSnapshot(
            id: snapshotID,
            videoID: video.id,
            title: video.title,
            state: .queued,
            createdAt: .now
        ))

        let destination = Self.fileURL(for: video.id)
        let downloadsDir = destination.deletingLastPathComponent()
        let stem = destination.deletingPathExtension().lastPathComponent
        log.debug("download[\(video.id, privacy: .public)] destination=\(destination.path, privacy: .public)")

        // Pre-download filesystem work — creating the dir and scanning for stale siblings — runs
        // on a `.utility` background task instead of blocking the main actor. With several
        // parallel downloads this saves measurable scroll-hitch time on every Download All tap.
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            } catch {
                // Best-effort — directory probably already exists from a prior download.
            }
            if let siblings = try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil) {
                for url in siblings where url.lastPathComponent.hasPrefix("\(stem).") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }.value

        if try await tryNativeDownload(
            video: video,
            quality: quality,
            destination: destination,
            snapshotID: snapshotID,
            startedAt: startedAt
        ) {
            return destination
        }

        do {
            log.info("download[\(video.id, privacy: .public)] source=youtubekit")
            try await runYouTubeKitFallback(
                video: video,
                quality: quality,
                destination: destination,
                snapshotID: snapshotID
            )
            try Task.checkCancellation()
            try await mediaFinalizer.validateFile(at: destination, quality: quality, videoID: video.id)
            try Task.checkCancellation()
            await metadataWriter.persist(video: video, fileURL: destination)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .completed(destination), createdAt: .now
            ))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.taskRegistry.remove(snapshotID)
                self.publishSnapshots()
            }
            log.info("download[\(video.id, privacy: .public)] source=youtubekit success in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)), privacy: .public)s")
            return destination
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            log.error("download[\(video.id, privacy: .public)] source=youtubekit failed: \(String(describing: error), privacy: .public)")
            let failure = DownloadFailure.wrapping(error)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .failed(failure.localizedDescription), createdAt: .now
            ))
            throw failure
        }
    }

    /// Tries the playback resolver's source first, including one signed-URL refresh on authorization failure.
    /// A non-cancellation failure returns false so the YouTubeKit direct-format path can take over.
    private func tryNativeDownload(
        video: Video,
        quality: VideoQuality,
        destination: URL,
        snapshotID: String,
        startedAt: Date
    ) async throws -> Bool {
        do {
            log.info("native-download[\(video.id, privacy: .public)] resolving playback source")
            phaseByVideoID[video.id] = "stream"
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .downloading(progress: 0), createdAt: .now
            ))
            let resolved = try await sourceSelector.nativeSource(video: video, quality: quality)
            try Task.checkCancellation()
            try await downloadResolvedSource(
                resolved,
                to: destination,
                audioOnly: quality == .audioOnly,
                quality: quality,
                video: video,
                snapshotID: snapshotID
            )
            try Task.checkCancellation()
            try await mediaFinalizer.validateFile(at: destination, quality: quality, videoID: video.id)
            await metadataWriter.persist(video: video, fileURL: destination)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .completed(destination), createdAt: .now
            ))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.taskRegistry.remove(snapshotID)
                self.publishSnapshots()
            }
            log.info("download[\(video.id, privacy: .public)] source=native success in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)), privacy: .public)s")
            return true
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            if NativeHLSDownloadService.isAuthorizationFailure(error) {
                log.notice("native-download[\(video.id, privacy: .public)] authorization failed; invalidating the signed URL and resolving once more")
                await StreamURLCache.shared.remove(videoID: video.id, formatID: "native-\(quality.rawValue)")
                await StreamURLCache.shared.remove(videoID: video.id, formatID: "native-paired-\(quality.rawValue)")
                do {
                    let refreshed = try await sourceSelector.nativeSource(video: video, quality: quality)
                    try await downloadResolvedSource(
                        refreshed,
                        to: destination,
                        audioOnly: quality == .audioOnly,
                        quality: quality,
                        video: video,
                        snapshotID: snapshotID
                    )
                    try await mediaFinalizer.validateFile(at: destination, quality: quality, videoID: video.id)
                    await metadataWriter.persist(video: video, fileURL: destination)
                    publish(snapshot: DownloadTaskSnapshot(
                        id: snapshotID, videoID: video.id, title: video.title,
                        state: .completed(destination), createdAt: .now
                    ))
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.taskRegistry.remove(snapshotID)
                        self.publishSnapshots()
                    }
                    log.info("download[\(video.id, privacy: .public)] source=native success after fresh resolution")
                    return true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    log.notice("native-download[\(video.id, privacy: .public)] fresh-resolution retry failed: \(String(describing: error), privacy: .public)")
                }
            }
            try Task.checkCancellation()
            log.notice("native-download[\(video.id, privacy: .public)] failed: \(String(describing: error), privacy: .public); trying YouTubeKit")
        }
        return false
    }

    /// Renders a download progress event into a snapshot and a log line.
    private func handleProgress(
        status: String,
        downloaded: Int,
        total: Int,
        speed: Int,
        eta: Int,
        phase: String,
        snapshotID: String,
        videoID: String,
        videoTitle: String
    ) {
        guard !taskRegistry.isCancelled(snapshotID) else { return }
        let progress = total > 0 ? max(0, min(1, Double(downloaded) / Double(total))) : 0

        if status == "downloading" {
            // Throttle: skip if this video's last publish was within the min-interval window. The
            // next callback that arrives outside the window will pick up the latest progress
            // value, so the UI stays accurate, just less twitchy.
            guard taskRegistry.shouldPublishProgress(for: videoID) else { return }

            log.debug("download[\(videoID, privacy: .public)] \(phase, privacy: .public) progress: \(String(format: "%.1f", progress * 100), privacy: .public)% (\(downloaded, privacy: .public)/\(total, privacy: .public) B) speed=\(speed, privacy: .public) B/s eta=\(eta, privacy: .public)s")
            // Avoid an Observable write when the phase didn't actually change. SwiftUI's
            // `@Observable` macro fires on every assignment, even to the same value.
            if phaseByVideoID[videoID] != phase {
                phaseByVideoID[videoID] = phase
            }
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID,
                videoID: videoID,
                title: videoTitle,
                state: .downloading(progress: progress),
                createdAt: .now
            ))
        } else if status == "finished" {
            log.info("download[\(videoID, privacy: .public)] \(phase, privacy: .public) finished — moving to next phase")
            // Keep overall progress visible while the next track or finalization starts.
            // Reset throttle so the next phase (audio after video, or mux) gets its first event
            // through immediately rather than waiting out the window from the previous phase.
            taskRegistry.resetProgressThrottle(for: videoID)
            // Note: don't clear phase here — keep showing the last label until the next downloading
            // event sets it.
        } else if status == "error" {
            log.error("download[\(videoID, privacy: .public)] progress hook reports error")
            taskRegistry.resetProgressThrottle(for: videoID)
        } else {
            log.debug("download[\(videoID, privacy: .public)] progress hook status=\(status, privacy: .public)")
        }
    }

    // MARK: - YouTubeKit / TVHTML5 fallback

    /// Direct-format fallback; uses a User-Agent matching the client that minted the URLs.
    private func runYouTubeKitFallback(video: Video, quality: VideoQuality, destination: URL, snapshotID: String) async throws {
        log.info("youtube-kit-download[\(video.id, privacy: .public)] fetching stream info")
        publish(snapshot: DownloadTaskSnapshot(
            id: snapshotID, videoID: video.id, title: video.title,
            state: .downloading(progress: 0), createdAt: .now
        ))
        phaseByVideoID[video.id] = "stream"

        guard let source = await sourceSelector.fallbackSource(videoID: video.id) else {
            throw DownloadFailure.noFormats
        }
        let formats = source.formats
        let client = source.client
        log.info("youtube-kit-download[\(video.id, privacy: .public)] \(formats.count, privacy: .public) usable formats client=\(String(describing: client), privacy: .public)")
        let maxHeight = DownloadFormatPolicy.targetHeight(for: quality)

        try? FileManager.default.removeItem(at: destination)

        if quality == .audioOnly {
            guard let audioFormat = DownloadFormatPolicy.pickBestAudioOnly(formats: formats),
                  let audioURL = audioFormat.url,
                  audioFormat.mimeType.lowercased().contains("mp4") || audioFormat.mimeType.lowercased().contains("m4a") else {
                throw DownloadFailure.noFormats
            }
            let audioFile = destination.deletingPathExtension().appendingPathExtension("fallback.audio.m4a")
            defer { try? FileManager.default.removeItem(at: audioFile) }
            phaseByVideoID[video.id] = "audio"
            try await downloadStream(
                from: audioURL, to: audioFile, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                client: client
            )
            try Task.checkCancellation()
            phaseByVideoID[video.id] = "muxing"
            let exit = await FFmpegRunner.shared.run([
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", audioFile.path, "-map", "0:a:0", "-vn", "-c:a", "copy",
                "-movflags", "+faststart", destination.path
            ])
            try Task.checkCancellation()
            guard exit == 0 else { throw DownloadFailure.remuxFailed }
            return
        }

        // Progressive single-file first (itag 18); otherwise adaptive A/V + remux.
        if let progressive = DownloadFormatPolicy.pickBestProgressive(formats: formats, maxHeight: maxHeight),
           let url = progressive.url {
            log.info("youtube-kit-download[\(video.id, privacy: .public)] progressive height=\(progressive.height ?? 0, privacy: .public)")
            try await downloadStream(
                from: url, to: destination, videoID: video.id,
                snapshotID: snapshotID, title: video.title, client: client
            )
            return
        }

        let videoFormat = DownloadFormatPolicy.pickBestVideoOnly(formats: formats, maxHeight: maxHeight)
        let audioFormat = DownloadFormatPolicy.pickBestAudioOnly(formats: formats)
        guard let videoFormat, let videoURL = videoFormat.url,
              let audioFormat, let audioURL = audioFormat.url else {
            log.error("youtube-kit-download[\(video.id, privacy: .public)] no suitable formats found")
            throw DownloadFailure.noFormats
        }

        let downloadsDir = destination.deletingLastPathComponent()
        let stem = destination.deletingPathExtension().lastPathComponent
        let videoFile = downloadsDir.appendingPathComponent("\(stem).fallback.video.mp4")
        let audioFile = downloadsDir.appendingPathComponent("\(stem).fallback.audio.m4a")
        defer {
            try? FileManager.default.removeItem(at: videoFile)
            try? FileManager.default.removeItem(at: audioFile)
        }

        log.info("youtube-kit-download[\(video.id, privacy: .public)] adaptive video height=\(videoFormat.height ?? 0, privacy: .public)")
        phaseByVideoID[video.id] = "video"
        try await downloadFallbackMedia(
            from: videoURL, to: videoFile, videoID: video.id,
            snapshotID: snapshotID, title: video.title, client: client,
            alternateURLs: DownloadFormatPolicy.alternateVideoOnlyURLs(
                formats: formats, maxHeight: maxHeight, excluding: videoURL
            )
        )
        phaseByVideoID[video.id] = "audio"
        try await downloadFallbackMedia(
            from: audioURL, to: audioFile, videoID: video.id,
            snapshotID: snapshotID, title: video.title, client: client,
            alternateURLs: DownloadFormatPolicy.alternateAudioOnlyURLs(
                formats: formats, excluding: audioURL
            )
        )
        phaseByVideoID[video.id] = "muxing"

        try await mediaFinalizer.mux(video: videoFile, audio: audioFile, destination: destination)
    }

    /// Bridges byte progress from the shared direct transfer into this download's UI snapshot.
    private func downloadStream(
        from url: URL,
        to destination: URL,
        videoID: String,
        snapshotID: String,
        title: String,
        client: DownloadClientIdentity? = nil,
        sourceLabel: String = "fallback"
    ) async throws {
        let reportProgress: @Sendable (Int64, Int64) -> Void = { [weak self] written, total in
            Task { @MainActor [weak self] in
                guard let self,
                      let snapshot = self.taskRegistry.snapshot(for: snapshotID),
                      case .downloading = snapshot.state else { return }
                self.handleProgress(
                    status: "downloading",
                    downloaded: Int(clamping: written),
                    total: Int(clamping: total),
                    speed: 0,
                    eta: 0,
                    phase: self.phaseByVideoID[videoID] ?? "stream",
                    snapshotID: snapshotID,
                    videoID: videoID,
                    videoTitle: title
                )
            }
        }
        try await streamTransfer.download(
            from: url,
            to: destination,
            client: client,
            sourceLabel: sourceLabel,
            onProgress: reportProgress
        )
    }

    /// Tries the primary URL, then a couple of alternate itags on CDN 403.
    private func downloadFallbackMedia(
        from url: URL,
        to destination: URL,
        videoID: String,
        snapshotID: String,
        title: String,
        client: DownloadClientIdentity,
        alternateURLs: [URL]
    ) async throws {
        var candidates = [url] + alternateURLs
        // Cap retries so a blocked video does not walk every itag.
        if candidates.count > 3 { candidates = Array(candidates.prefix(3)) }
        var lastError: Error = DownloadFailure.unavailable
        for (index, candidate) in candidates.enumerated() {
            do {
                try await downloadStream(
                    from: candidate, to: destination, videoID: videoID,
                    snapshotID: snapshotID, title: title, client: client
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as DownloadFailure where failure == .forbidden {
                lastError = failure
                log.notice("youtube-kit-download[\(videoID, privacy: .public)] CDN forbidden on attempt \(index + 1, privacy: .public)/\(candidates.count, privacy: .public); trying next format")
                continue
            } catch {
                throw error
            }
        }
        throw lastError
    }

    /// Materializes the native source used by playback. HLS, direct MP4, and separate MP4/M4A
    /// streams have distinct transfer paths; treating a video-only URL as a complete file would
    /// fail final validation and needlessly invoke the direct-format fallback.
    private func downloadResolvedSource(
        _ source: NativeStreamResult,
        to destination: URL,
        audioOnly: Bool,
        quality: VideoQuality,
        video: Video,
        snapshotID: String
    ) async throws {
        if source.mediaKind == .paired {
            guard let audioURL = source.audioURL else {
                throw DownloadFailure.noFormats
            }
            guard !audioOnly else { throw DownloadFailure.noFormats }
            let temporaryVideo = destination.deletingPathExtension().appendingPathExtension("native.video.mp4")
            let temporaryAudio = destination.deletingPathExtension().appendingPathExtension("native.audio.m4a")
            defer {
                try? FileManager.default.removeItem(at: temporaryVideo)
                try? FileManager.default.removeItem(at: temporaryAudio)
            }
            phaseByVideoID[video.id] = "video"
            try await downloadStream(
                from: source.url, to: temporaryVideo, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                sourceLabel: "native-video"
            )
            try Task.checkCancellation()
            phaseByVideoID[video.id] = "audio"
            try await downloadStream(
                from: audioURL, to: temporaryAudio, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                sourceLabel: "native-audio"
            )
            try Task.checkCancellation()
            phaseByVideoID[video.id] = "muxing"
            let exit = await FFmpegRunner.shared.run([
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", temporaryVideo.path, "-i", temporaryAudio.path,
                "-map", "0:v:0", "-map", "1:a:0", "-c", "copy",
                "-movflags", "+faststart", destination.path
            ])
            try Task.checkCancellation()
            guard exit == 0 else { throw DownloadFailure.remuxFailed }
            return
        }

        if audioOnly, source.mediaKind == .direct {
            log.info("native-download[\(video.id, privacy: .public)] direct progressive audio transfer")
            phaseByVideoID[video.id] = "audio"
            let temporaryAudio = destination.deletingPathExtension().appendingPathExtension("audio.m4a")
            defer { try? FileManager.default.removeItem(at: temporaryAudio) }
            try await downloadStream(
                from: source.url,
                to: temporaryAudio,
                videoID: video.id,
                snapshotID: snapshotID,
                title: video.title,
                sourceLabel: "native-audio"
            )
            try Task.checkCancellation()
            phaseByVideoID[video.id] = "muxing"
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .downloading(progress: 0), createdAt: .now
            ))
            let exit = await FFmpegRunner.shared.run([
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
                "-i", temporaryAudio.path, "-map", "0:a:0", "-vn", "-c:a", "copy",
                "-movflags", "+faststart", destination.path
            ])
            try Task.checkCancellation()
            guard exit == 0 else { throw DownloadFailure.remuxFailed }
            return
        }

        if source.mediaKind == .direct {
            phaseByVideoID[video.id] = "stream"
            try await downloadStream(
                from: source.url, to: destination, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                sourceLabel: "native-video"
            )
            return
        }

        let fragmentCount = max(1, min(16, preferences.concurrentFragments))
        log.info("native-download[\(video.id, privacy: .public)] native HLS transfer concurrency=\(fragmentCount, privacy: .public)")
        try await NativeHLSDownloadService().download(
            manifestURL: source.url,
            destination: destination,
            maximumHeight: quality.heightCap ?? 1080,
            audioOnly: audioOnly,
            concurrency: fragmentCount
        ) { [weak self] progress in
            Task { @MainActor in
                guard let self else { return }
                self.handleProgress(
                    status: "downloading",
                    downloaded: Int(progress * 10_000),
                    total: 10_000,
                    speed: 0,
                    eta: 0,
                    phase: audioOnly ? "audio" : "stream",
                    snapshotID: snapshotID,
                    videoID: video.id,
                    videoTitle: video.title
                )
            }
        }
    }

    // MARK: - File locations + format selection

    /// Documents/`<videoID>.mp4` — visible in Files via UIFileSharingEnabled.
    static func fileURL(for videoID: String) -> URL {
        downloadsDirectory.appendingPathComponent("\(videoID).mp4")
    }

    private static let downloadsDirectory = AppDirectories.documents

    // MARK: - Snapshots

    private func publish(snapshot: DownloadTaskSnapshot) {
        // Progress callbacks already queued on the main actor can outlive cancellation.
        guard let snapshot = taskRegistry.publish(
            snapshot,
            phase: phaseByVideoID[snapshot.videoID] ?? "stream"
        ) else { return }
        if case .downloading(let value) = snapshot.state {
            progressByVideoID[snapshot.videoID] = value
        } else if case .completed = snapshot.state {
            progressByVideoID.removeValue(forKey: snapshot.videoID)
        } else if case .failed = snapshot.state {
            progressByVideoID.removeValue(forKey: snapshot.videoID)
        }
        publishSnapshots()
    }

    private func publishSnapshots() {
        activeTasks = taskRegistry.snapshots
        log.debug("publishSnapshots: \(self.activeTasks.count, privacy: .public) entries")
    }
}
