import AVFoundation
import CoreMedia
import Foundation
import Network
import OSLog
import PythonKit
import SwiftData
import UIKit
import YoutubeDL

/// Owns the on-disk video cache, coordinates native HLS downloads, and surfaces progress so UI can
/// render a live transfer queue. Embedded yt-dlp is retained only as a compatibility fallback.
///
/// **Playback contract (CLAUDE.md §7 amended):**
/// Explicit downloads call `ensureDownloaded(video:quality:)`. An existing `Documents/<id>.mp4`
/// returns immediately; otherwise the playback resolver supplies a working HLS manifest and
/// `NativeHLSDownloadService` materializes it. Successful files receive `DownloadMetadata` xattrs.
///
/// **Progress:** the manager publishes a single `AsyncStream<[DownloadTaskSnapshot]>` that any
/// observer can subscribe to. Both the Downloads screen and the per-tab badge read from it.
@available(iOS 17.0, *)
@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    /// Live snapshots of every in-flight + recently completed download. Both the Downloads screen
    /// and the tab-badge model observe this directly via `@Observable`. Previous design used a
    /// single-consumer `AsyncStream` which silently dropped events for the second subscriber — that
    /// is why the Downloads tab looked empty while the badge was incrementing.
    private(set) var activeTasks: [DownloadTaskSnapshot] = []

    /// Per-video downloaded progress (0…1). The player observes this so the mini-player and the
    /// full-screen player can render a progress overlay while a file is being fetched.
    private(set) var progressByVideoID: [String: Double] = [:]
    /// Per-video human-readable phase label ("video", "audio", "muxing"). yt-dlp downloads multiple
    /// streams sequentially under the same id, so we surface which one is currently in-flight to
    /// avoid the confusing "Downloading 100%" → "Downloading 0%" → "Downloading 100%" sequence.
    private(set) var phaseByVideoID: [String: String] = [:]

    private var tasks: [String: DownloadTaskSnapshot] = [:]
    private struct RetryRequest {
        let video: Video
        let quality: VideoQuality
    }
    /// Failed rows keep their original selection, so Retry never silently changes quality.
    private var retryRequests: [String: RetryRequest] = [:]
    @ObservationIgnored private var overallProgress: [String: DownloadOverallProgress] = [:]
    @ObservationIgnored private var cancelledSnapshotIDs: [String] = []

    /// Throttles the progress publish stream. yt-dlp emits progress events 5–10× per second per
    /// active download, and each `publish(snapshot:)` writes to 3 `@Observable` dictionaries plus
    /// rebuilds `activeTasks`. With several parallel downloads (Download All) the main actor was
    /// processing 30+ Observable mutations per second, and SwiftUI's per-mutation diff pass was
    /// what users felt as "scrolling stutters while downloading". We coalesce: if a video's most
    /// recent publish was less than `progressPublishMinInterval` ago, the new event is dropped.
    /// The next event arriving after the window catches up automatically, and terminal events
    /// (`finished` / `error`) bypass throttling entirely so we never miss a completion.
    private var lastProgressPublishedAt: [String: ContinuousClock.Instant] = [:]
    private let progressPublishMinInterval: Duration = .milliseconds(200)

    /// Coalesces concurrent `ensureDownloaded` calls for the same video so we don't start two
    /// downloads in parallel for the same id (which would race on the destination path).
    private var inflight: [String: Task<URL, Error>] = [:]
    private let preferences = UserPreferences()
    @ObservationIgnored private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    private var currentPath: NWPath?

    private init() {
        // Force the lazy static while the app still owns its original container environment;
        // embedded Python initialization can otherwise affect later directory resolution.
        _ = Self.downloadsDirectory
        startMonitoringPath()
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
              size.int64Value >= Self.minimumDownloadSize else {
            return nil
        }
        return url
    }

    /// Either returns the existing local file URL, or downloads the video via yt-dlp and returns
    /// the freshly-written path. Coalesces parallel callers for the same `videoID`.
    ///
    /// `priority` controls where the download lands in `PythonRunner`'s queue. `.userInitiated`
    /// — the call comes from a play tap, the user is actively waiting — jumps ahead of any
    /// pending `.background` items (playlist Download All, queue prefetch). The currently-running
    /// yt-dlp cannot be preempted, but the new high-priority item runs immediately after it.
    func ensureDownloaded(video: Video, quality: VideoQuality, priority: DownloadPriority = .background) async throws -> URL {
        try Task.checkCancellation()
        log.info("ensureDownloaded(\(video.id, privacy: .public)) — title=\"\(video.title, privacy: .public)\" quality=\(quality.rawValue, privacy: .public) priority=\(String(describing: priority), privacy: .public)")
        if let existing = localFile(for: video.id) {
            log.info("ensureDownloaded(\(video.id, privacy: .public)): cache hit, skipping yt-dlp")
            Task { await OfflineCaptionStore.shared.downloadAvailableTracks(for: video.id) }
            return existing
        }

        if let inflightTask = inflight[video.id] {
            log.info("ensureDownloaded(\(video.id, privacy: .public)): joining inflight task")
            return try await inflightTask.value
        }

        let supersededFailures = tasks.values.compactMap { snapshot -> String? in
            guard snapshot.videoID == video.id, case .failed = snapshot.state else { return nil }
            return snapshot.id
        }
        for id in supersededFailures {
            tasks[id] = nil
            retryRequests[id] = nil
        }
        if !supersededFailures.isEmpty { publishSnapshots() }

        log.info("ensureDownloaded(\(video.id, privacy: .public)): checking network gate (allowCellular=\(self.preferences.allowCellularDownloads, privacy: .public))")
        do {
            try await waitForAllowedNetwork()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let snapshotID = UUID().uuidString
            retryRequests[snapshotID] = RetryRequest(video: video, quality: quality)
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

        let task = Task<URL, Error> { @MainActor [weak self] in
            guard let self else { throw YouTubeServiceError.unknown(NSError(domain: "DownloadManager", code: -1)) }
            defer { self.inflight[video.id] = nil }
            return try await self.runYoutubeDLDownload(video: video, quality: quality, priority: priority)
        }
        inflight[video.id] = task
        return try await task.value
    }

    /// Removes the downloaded file (if any) plus its SwiftData row. Safe to call when nothing is on
    /// disk — just no-ops. The `context` parameter is kept for source compatibility but the actual
    /// SwiftData delete now goes through the background `PersistenceWriter` so we don't block the
    /// main thread on the SQL queue.
    func deleteDownloaded(videoID: String, context: ModelContext) {
        let url = Self.fileURL(for: videoID)
        // File-system backed: removing the file drops its xattr too. `DownloadsStore` posts
        // the change notification on our behalf so the Downloads tab refreshes.
        DownloadsStore.shared.delete(at: url)
        log.info("Deleted download \(videoID, privacy: .public)")
    }

    func cancel(taskID: String) {
        guard let snapshot = tasks[taskID] else { return }
        cancelledSnapshotIDs.append(taskID)
        if cancelledSnapshotIDs.count > 256 { cancelledSnapshotIDs.removeFirst() }
        overallProgress[taskID] = nil
        progressByVideoID[snapshot.videoID] = nil
        phaseByVideoID[snapshot.videoID] = nil
        tasks[taskID] = nil
        retryRequests[taskID] = nil
        publishSnapshots()
        if let task = inflight[snapshot.videoID] {
            task.cancel()
            inflight[snapshot.videoID] = nil
        }
    }

    /// Starts a fresh attempt for a failed transfer using its original video and quality.
    /// This is a retry from the beginning, not a claim that HLS/yt-dlp can resume partial bytes.
    func retry(taskID: String) async throws {
        guard let snapshot = tasks[taskID], case .failed = snapshot.state,
              let request = retryRequests[taskID] else {
            throw NSError(
                domain: "com.leshko.freetube.download",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This download can no longer be retried. Start it again from the video."]
            )
        }

        // A failure snapshot can be published just before the previous task's defer clears
        // `inflight`. Await it so ensureDownloaded does not join that failed attempt.
        if let previous = inflight[snapshot.videoID] {
            _ = try? await previous.value
        }
        tasks[taskID] = nil
        retryRequests[taskID] = nil
        publishSnapshots()
        do {
            _ = try await ensureDownloaded(
                video: request.video,
                quality: request.quality,
                priority: .userInitiated
            )
        } catch {
            // A network gate can fail before the new attempt creates a snapshot. Restore
            // the retryable row in that case; actual transfer failures publish their own row.
            if !tasks.values.contains(where: { $0.videoID == snapshot.videoID }) {
                tasks[taskID] = snapshot
                retryRequests[taskID] = request
                publishSnapshots()
            }
            throw error
        }
    }

    // MARK: - yt-dlp execution

    private func runYoutubeDLDownload(video: Video, quality: VideoQuality, priority: DownloadPriority = .background) async throws -> URL {
        let startedAt = Date()
        log.info("yt-dlp[\(video.id, privacy: .public)] runYoutubeDLDownload start quality=\(quality.rawValue, privacy: .public)")
        let snapshotID = UUID().uuidString
        retryRequests[snapshotID] = RetryRequest(video: video, quality: quality)
        log.debug("yt-dlp[\(video.id, privacy: .public)] snapshotID=\(snapshotID, privacy: .public) → state=queued")
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
        log.debug("yt-dlp[\(video.id, privacy: .public)] destination=\(destination.path, privacy: .public)")

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

        return try await runCompatibilityDownload(
            video: video,
            quality: quality,
            priority: priority,
            destination: destination,
            snapshotID: snapshotID,
            startedAt: startedAt
        )
    }

    /// Runs the serialized yt-dlp compatibility path after native stream download has failed.
    private func runCompatibilityDownload(
        video: Video,
        quality: VideoQuality,
        priority: DownloadPriority,
        destination: URL,
        snapshotID: String,
        startedAt: Date
    ) async throws -> URL {
        let downloadsDir = destination.deletingLastPathComponent()
        let stem = destination.deletingPathExtension().lastPathComponent

        // Use `,` (download multiple formats as separate files) instead of `+` (download + merge
        // via ffmpeg). yt-dlp's ffmpeg merger reliably hangs on iOS — once `Popen.communicate`
        // dispatches the merger ffmpeg subprocess we never see Python return. We mux the tracks
        // through the serialized in-process FFmpeg runner. We still keep a single-file fallback
        // (`best[ext=mp4]/best`) for the rare case where YouTube serves a combined progressive file.
        let formatString = DownloadFormatPolicy.formatString(for: quality)
        log.debug("yt-dlp[\(video.id, privacy: .public)] format selector=\(formatString, privacy: .public)")
        // Output template includes `%(format_id)s` so individual streams land at predictable paths
        // we can find afterwards. Final destination is set by us after the Swift-side mux.
        let outputTemplate = destination.deletingPathExtension().path + ".%(format_id)s-%(vcodec)s-%(acodec)s.%(ext)s"

        let argv = DownloadFormatPolicy.youtubeDLArguments(
            video: video,
            formatString: formatString,
            outputTemplate: outputTemplate,
            concurrentFragments: preferences.concurrentFragments
        )

        log.info("yt-dlp[\(video.id, privacy: .public)] argv=\(argv.joined(separator: " "), privacy: .public)")
        log.debug("yt-dlp[\(video.id, privacy: .public)] → state=downloading(0)")
        publish(snapshot: DownloadTaskSnapshot(
            id: snapshotID,
            videoID: video.id,
            title: video.title,
            state: .downloading(progress: 0),
            createdAt: .now
        ))

        do {
            log.info("yt-dlp[\(video.id, privacy: .public)] invoking yt_dlp() — first launch triggers Python module download (serialized on dedicated thread via PythonRunner)")
            try await PythonRunner.shared.run(argv: argv, progress: { [weak self] dict in
                guard let self else { return }
                // CRITICAL: PythonKit's `PythonObject` is reference-counted on Python's GIL thread.
                // If we capture the `[String: PythonObject]` dict into a `Task { @MainActor in ... }`
                // closure, the objects get released on a *different* thread when the task ends, and
                // PyReference.deinit crashes inside `_PyInterpreterState_GET`. So we must extract
                // every value we care about into Swift-native primitives RIGHT HERE on the calling
                // thread, then ship only those primitives across the actor boundary.
                let status = String(dict["status"] ?? "") ?? ""
                let downloaded = Int(dict["downloaded_bytes"] ?? 0) ?? 0
                let total = Int(dict["total_bytes"] ?? dict["total_bytes_estimate"] ?? 0) ?? 0
                let speed = Int(dict["speed"] ?? 0) ?? 0
                let eta = Int(dict["eta"] ?? 0) ?? 0
                // `filename` tells us which stream this hook is for: <id>.<itag>.mp4 vs <id>.<itag>.m4a.
                let filename = String(dict["filename"] ?? "") ?? ""
                let phase: String
                let lower = filename.lowercased()
                if lower.hasSuffix(".m4a") || lower.hasSuffix(".webm") && lower.contains("audio") {
                    phase = "audio"
                } else if lower.hasSuffix(".mp4") || lower.hasSuffix(".webm") {
                    phase = "video"
                } else {
                    phase = "stream"
                }
                Task { @MainActor [snapshotID, videoID = video.id, videoTitle = video.title] in
                    self.handleProgress(
                        status: status,
                        downloaded: downloaded,
                        total: total,
                        speed: speed,
                        eta: eta,
                        phase: phase,
                        snapshotID: snapshotID,
                        videoID: videoID,
                        videoTitle: videoTitle
                    )
                }
            }, log: { [weak self, log] level, message in
                // Bridge yt-dlp's Python logger to os_log so its diagnostics show up alongside ours.
                // Levels we get: debug / info / warning / error.
                if level == "error" {
                    log.error("yt-dlp: \(message, privacy: .public)")
                } else if level == "warning" {
                    log.notice("yt-dlp: \(message, privacy: .public)")
                } else {
                    log.info("yt-dlp: \(message, privacy: .public)")
                }
                // The "[Merger]" line is yt-dlp's last visible step before it hands off to ffmpeg.
                // Preserve overall progress during finalization instead of replacing it with
                // an indeterminate spinner or resetting to zero between tracks.
                if message.contains("[Merger]") || message.contains("[ExtractAudio]") || message.contains("Fixup") {
                    let id = video.id
                    Task { @MainActor in
                        guard let self, let snapshot = self.tasks[snapshotID],
                              !self.cancelledSnapshotIDs.contains(snapshotID) else { return }
                        self.phaseByVideoID[id] = "muxing"
                        self.publish(snapshot: DownloadTaskSnapshot(
                            id: snapshot.id, videoID: id, title: snapshot.title,
                            state: .downloading(progress: 0), createdAt: snapshot.createdAt
                        ))
                    }
                }
            }, priority: priority == .userInitiated ? .high : .low)
        } catch {
            try Task.checkCancellation()
            log.error("yt-dlp[\(video.id, privacy: .public)] threw: \(String(describing: error), privacy: .public)")
            // **Don't fail yet** — try the YouTubeKit / TVHTML5_SIMPLY_EMBEDDED_PLAYER fallback
            // before giving up. yt-dlp's no-JS-runtime path can produce "This video is not
            // available" for entire classes of videos (kids content, PoT-gated music videos,
            // some live recordings) where YouTubeKit's tvHtmlModel still returns playable URLs
            // because that client profile is exempt from PoT enforcement on the video-info side.
            do {
                try await runYouTubeKitFallback(video: video, quality: quality, destination: destination, snapshotID: snapshotID)
                try await validateDownloadedFile(at: destination, quality: quality, videoID: video.id)
                let dur = Date().timeIntervalSince(startedAt)
                log.info("yt-dlp[\(video.id, privacy: .public)] FALLBACK SUCCESS in \(String(format: "%.1f", dur), privacy: .public)s")
                await persistDownloaded(video: video, fileURL: destination)
                publish(snapshot: DownloadTaskSnapshot(
                    id: snapshotID, videoID: video.id, title: video.title,
                    state: .completed(destination), createdAt: .now
                ))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.tasks[snapshotID] = nil
                    self.publishSnapshots()
                }
                return destination
            } catch {
                log.error("yt-dlp[\(video.id, privacy: .public)] YouTubeKit fallback also failed: \(String(describing: error), privacy: .public)")
                try? FileManager.default.removeItem(at: destination)
                publish(snapshot: DownloadTaskSnapshot(
                    id: snapshotID,
                    videoID: video.id,
                    title: video.title,
                    state: .failed(error.localizedDescription),
                    createdAt: .now
                ))
                throw YouTubeServiceError.streamExtractionFailed
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        log.info("yt-dlp[\(video.id, privacy: .public)] returned after \(String(format: "%.1f", elapsed), privacy: .public)s — locating output files")

        // yt-dlp wrote either individual streams or one progressive fallback. Run the candidate
        // scan off-main since `contentsOfDirectory` on a Downloads folder with hundreds of files
        // becomes a noticeable hitch.
        let intermediates: [URL] = await Task.detached(priority: .utility) {
            let candidates = (try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil))?
                .filter { $0.lastPathComponent.hasPrefix("\(stem).") } ?? []
            // Don't include the canonical destination itself in mux inputs.
            return candidates.filter { $0.path != destination.path }
        }.value
        var intermediatesToClean = intermediates
        defer {
            // A failed mux or later validation must not leave large separate tracks on disk.
            // Success awaits this cleanup below before publishing the completed download.
            let leftovers = intermediatesToClean
            if !leftovers.isEmpty {
                Task.detached(priority: .utility) {
                    for url in leftovers { try? FileManager.default.removeItem(at: url) }
                }
            }
        }
        log.debug("yt-dlp[\(video.id, privacy: .public)] candidate files: \(intermediates.map(\.lastPathComponent).joined(separator: ", "), privacy: .public)")

        // The output template records both codec roles. This is reliable even when the only
        // available audio is WebM/Opus (an extension-only scan used to mistake it for video).
        let videoFile = intermediates.first { $0.lastPathComponent.contains("-none.") }
        let audioFile = intermediates.first { $0.lastPathComponent.contains("-none-") }

        if let videoFile, let audioFile {
            log.info("yt-dlp[\(video.id, privacy: .public)] muxing video=\(videoFile.lastPathComponent, privacy: .public) audio=\(audioFile.lastPathComponent, privacy: .public)")
            do {
                try await muxToDestination(video: videoFile, audio: audioFile, destination: destination)
            } catch {
                log.error("yt-dlp[\(video.id, privacy: .public)] Swift-side mux failed: \(String(describing: error), privacy: .public)")
                publish(snapshot: DownloadTaskSnapshot(
                    id: snapshotID,
                    videoID: video.id,
                    title: video.title,
                    state: .failed("Could not combine video + audio"),
                    createdAt: .now
                ))
                throw YouTubeServiceError.streamExtractionFailed
            }
            // Clean up the per-stream intermediates off-main — `removeItem` for each one is sync,
            // and with N parallel downloads finishing back-to-back this can add up.
            let toRemove = intermediates
            await Task.detached(priority: .utility) {
                for url in toRemove {
                    try? FileManager.default.removeItem(at: url)
                }
            }.value
            intermediatesToClean = []
        } else if let single = intermediates.first {
            // Single combined progressive file — just rename it to the destination.
            log.info("yt-dlp[\(video.id, privacy: .public)] single-file mode (no mux needed): \(single.lastPathComponent, privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: single, to: destination)
            } catch {
                log.error("yt-dlp[\(video.id, privacy: .public)] could not move \(single.path, privacy: .public) → destination: \(String(describing: error), privacy: .public)")
                throw YouTubeServiceError.streamExtractionFailed
            }
        }

        if !FileManager.default.fileExists(atPath: destination.path) {
            log.notice("yt-dlp[\(video.id, privacy: .public)] post-mux: destination still missing — falling back to YouTubeKit/TVHTML5")
            // Mirror the catch-branch fallback for the "yt-dlp returned without writing"
            // case. Same TVHTML5_SIMPLY_EMBEDDED_PLAYER path — bypasses PoT for video-info,
            // then downloads via plain URLSession.
            do {
                try await runYouTubeKitFallback(video: video, quality: quality, destination: destination, snapshotID: snapshotID)
            } catch {
                log.error("yt-dlp[\(video.id, privacy: .public)] YouTubeKit fallback also failed: \(String(describing: error), privacy: .public)")
                publish(snapshot: DownloadTaskSnapshot(
                    id: snapshotID,
                    videoID: video.id,
                    title: video.title,
                    state: .failed("YouTube refused the download stream. Please try again."),
                    createdAt: .now
                ))
                throw YouTubeServiceError.streamExtractionFailed
            }
        }

        do {
            try await validateDownloadedFile(at: destination, quality: quality, videoID: video.id)
        } catch {
            log.error("yt-dlp[\(video.id, privacy: .public)] final validation failed: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID,
                videoID: video.id,
                title: video.title,
                state: .failed("The downloaded file was incomplete. Please try again."),
                createdAt: .now
            ))
            throw YouTubeServiceError.streamExtractionFailed
        }

        log.debug("yt-dlp[\(video.id, privacy: .public)] writing download metadata xattr")
        await persistDownloaded(video: video, fileURL: destination)

        log.debug("yt-dlp[\(video.id, privacy: .public)] → state=completed")
        publish(snapshot: DownloadTaskSnapshot(
            id: snapshotID,
            videoID: video.id,
            title: video.title,
            state: .completed(destination),
            createdAt: .now
        ))
        // Drop the completed entry from `tasks` after a moment so the in-progress section clears.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.tasks[snapshotID] = nil
            self.publishSnapshots()
        }

        log.info("yt-dlp[\(video.id, privacy: .public)] SUCCESS in \(String(format: "%.1f", elapsed), privacy: .public)s → \(destination.path, privacy: .public)")
        return destination
    }

    /// Tries the playback resolver's source first, including one signed-URL refresh on authorization failure.
    /// A non-cancellation failure returns false so the compatibility downloader can take over.
    private func tryNativeDownload(
        video: Video,
        quality: VideoQuality,
        destination: URL,
        snapshotID: String,
        startedAt: Date
    ) async throws -> Bool {
        // The app already has a fast, proven stream resolver for playback. Prefer that same
        // source for offline downloads instead of asking embedded yt-dlp to independently choose
        // a client and a PoT-gated format. For ordinary video this is an HLS master manifest;
        // FFmpeg downloads its media segments and remuxes them into the canonical local MP4.
        // A progressive/audio-only result follows the exact same path. yt-dlp remains below as a
        // compatibility fallback for videos for which the native resolver has no usable source.
        do {
            log.info("native-download[\(video.id, privacy: .public)] resolving playback source")
            phaseByVideoID[video.id] = "stream"
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .downloading(progress: 0), createdAt: .now
            ))
            let resolved = try await resolveNativeDownloadSource(video: video, quality: quality)
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
            try await validateDownloadedFile(at: destination, quality: quality, videoID: video.id)
            await persistDownloaded(video: video, fileURL: destination)
            publish(snapshot: DownloadTaskSnapshot(
                id: snapshotID, videoID: video.id, title: video.title,
                state: .completed(destination), createdAt: .now
            ))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.tasks[snapshotID] = nil
                self.publishSnapshots()
            }
            log.info("native-download[\(video.id, privacy: .public)] SUCCESS in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)), privacy: .public)s")
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
                    let refreshed = try await resolveNativeDownloadSource(video: video, quality: quality)
                    try await downloadResolvedSource(
                        refreshed,
                        to: destination,
                        audioOnly: quality == .audioOnly,
                        quality: quality,
                        video: video,
                        snapshotID: snapshotID
                    )
                    try await validateDownloadedFile(at: destination, quality: quality, videoID: video.id)
                    await persistDownloaded(video: video, fileURL: destination)
                    publish(snapshot: DownloadTaskSnapshot(
                        id: snapshotID, videoID: video.id, title: video.title,
                        state: .completed(destination), createdAt: .now
                    ))
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.tasks[snapshotID] = nil
                        self.publishSnapshots()
                    }
                    log.info("native-download[\(video.id, privacy: .public)] SUCCESS after fresh resolution")
                    return true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    log.notice("native-download[\(video.id, privacy: .public)] fresh-resolution retry failed: \(String(describing: error), privacy: .public)")
                }
            }
            try Task.checkCancellation()
            log.notice("native-download[\(video.id, privacy: .public)] failed: \(String(describing: error), privacy: .public); trying yt-dlp")
        }
        return false
    }

    /// Renders a yt-dlp progress event into a snapshot and a log line. Takes Swift primitives —
    /// PythonObject extraction happens upstream on Python's GIL thread, see the progress closure in
    /// `runYoutubeDLDownload`.
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
        guard !cancelledSnapshotIDs.contains(snapshotID) else { return }
        let progress = total > 0 ? max(0, min(1, Double(downloaded) / Double(total))) : 0

        if status == "downloading" {
            // Throttle: skip if this video's last publish was within the min-interval window. The
            // next callback that arrives outside the window will pick up the latest progress
            // value, so the UI stays accurate, just less twitchy.
            let now = ContinuousClock.now
            if let last = lastProgressPublishedAt[videoID], (now - last) < progressPublishMinInterval {
                return
            }
            lastProgressPublishedAt[videoID] = now

            log.debug("yt-dlp[\(videoID, privacy: .public)] \(phase, privacy: .public) progress: \(String(format: "%.1f", progress * 100), privacy: .public)% (\(downloaded, privacy: .public)/\(total, privacy: .public) B) speed=\(speed, privacy: .public) B/s eta=\(eta, privacy: .public)s")
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
            log.info("yt-dlp[\(videoID, privacy: .public)] \(phase, privacy: .public) finished — moving to next phase")
            // Keep overall progress visible while the next track or finalization starts.
            // Reset throttle so the next phase (audio after video, or mux) gets its first event
            // through immediately rather than waiting out the window from the previous phase.
            lastProgressPublishedAt.removeValue(forKey: videoID)
            // Note: don't clear phase here — keep showing the last label until the next downloading
            // event sets it.
        } else if status == "error" {
            log.error("yt-dlp[\(videoID, privacy: .public)] progress hook reports error")
            lastProgressPublishedAt.removeValue(forKey: videoID)
        } else {
            log.debug("yt-dlp[\(videoID, privacy: .public)] progress hook status=\(status, privacy: .public)")
        }
    }

    // MARK: - SwiftData

    private func persistDownloaded(video: Video, fileURL: URL) async {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let thumb = await downloadThumbnailData(url: video.thumbnailURL)
        log.debug("persistDownloaded(\(video.id, privacy: .public)) thumb=\(thumb == nil ? "nil" : "\(thumb!.count)B", privacy: .public) size=\(size, privacy: .public)")
        // File-system + xattr backed (no SwiftData): the metadata travels with the file.
        // `DownloadsStore.write` compresses the thumbnail to ~10 KB JPEG and posts the
        // change notification so the Downloads tab re-renders.
        DownloadsStore.shared.write(
            videoID: video.id,
            title: video.title,
            channelName: video.channelName,
            formatID: "ytdl",
            originalURL: nil,
            rawThumbnail: thumb,
            at: fileURL
        )
        log.info("persistDownloaded(\(video.id, privacy: .public)) wrote xattr size=\(size, privacy: .public) bytes")
        // Caption sidecars are optional and never hold up a completed media download.
        Task { await OfflineCaptionStore.shared.downloadAvailableTracks(for: video.id) }
    }

    private func downloadThumbnailData(url: URL?) async -> Data? {
        guard let url else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    // MARK: - YouTubeKit / TVHTML5 fallback

    /// Last-resort path that runs when yt-dlp fails to produce a usable file. Uses
    /// `VideoService.fetchInfoViaTVHTML5` (which goes through `YouTubeKitClient.tvHtmlModel`
    /// — TVHTML5_SIMPLY_EMBEDDED_PLAYER context, the client profile YouTube exempts from PoT
    /// enforcement) to get fresh stream URLs, then downloads the bytes directly via
    /// `URLSession`. If only adaptive (video-only + audio-only) streams are available, the
    /// two pieces are muxed back into a single `.mp4` via the same `FFmpegRunner` we use for
    /// yt-dlp output.
    ///
    /// Why this works when yt-dlp doesn't: yt-dlp's defensive filter strips formats marked as
    /// requiring a Proof-of-Origin token before download even starts. The TVHTML5 client
    /// returns URLs that aren't tagged with that requirement, so YouTubeKit happily hands them
    /// to us and URLSession fetches them like any other HTTPS resource.
    private func runYouTubeKitFallback(video: Video, quality: VideoQuality, destination: URL, snapshotID: String) async throws {
        log.info("yt-dlp[\(video.id, privacy: .public)] fallback: fetching stream info via YouTubeKit")
        publish(snapshot: DownloadTaskSnapshot(
            id: snapshotID, videoID: video.id, title: video.title,
            state: .downloading(progress: 0), createdAt: .now
        ))
        phaseByVideoID[video.id] = "stream"

        let formats = await fetchFallbackFormats(videoID: video.id)
        log.info("yt-dlp[\(video.id, privacy: .public)] fallback: \(formats.count, privacy: .public) usable formats")
        guard !formats.isEmpty else {
            throw YouTubeServiceError.streamExtractionFailed
        }
        let maxHeight = DownloadFormatPolicy.targetHeight(for: quality)

        try? FileManager.default.removeItem(at: destination)

        // **Strategy 1: progressive single-file format.** itag 18 (360p mp4 with both tracks)
        // ships as a single file, no mux step. Always tried first because it's the simplest
        // and fastest path when available.
        if let progressive = DownloadFormatPolicy.pickBestProgressive(formats: formats, maxHeight: maxHeight),
           let url = progressive.url {
            log.info("yt-dlp[\(video.id, privacy: .public)] fallback: progressive height=\(progressive.height ?? 0, privacy: .public)")
            try await downloadStream(from: url, to: destination, videoID: video.id, snapshotID: snapshotID, title: video.title)
            return
        }

        // **Strategy 2: adaptive — separate video-only and audio-only streams.** Required for
        // anything ≥ 720p (YouTube doesn't ship progressive at those resolutions). Download
        // both, then mux with ffmpeg `-c copy` so we get a single playable mp4.
        let videoFormat = DownloadFormatPolicy.pickBestVideoOnly(formats: formats, maxHeight: maxHeight)
        let audioFormat = DownloadFormatPolicy.pickBestAudioOnly(formats: formats)
        guard let videoFormat, let videoURL = videoFormat.url,
              let audioFormat, let audioURL = audioFormat.url else {
            log.error("yt-dlp[\(video.id, privacy: .public)] fallback: no suitable formats found")
            throw YouTubeServiceError.streamExtractionFailed
        }

        let downloadsDir = destination.deletingLastPathComponent()
        let stem = destination.deletingPathExtension().lastPathComponent
        let videoFile = downloadsDir.appendingPathComponent("\(stem).fallback.video.mp4")
        let audioFile = downloadsDir.appendingPathComponent("\(stem).fallback.audio.m4a")
        defer {
            try? FileManager.default.removeItem(at: videoFile)
            try? FileManager.default.removeItem(at: audioFile)
        }

        log.info("yt-dlp[\(video.id, privacy: .public)] fallback: adaptive video height=\(videoFormat.height ?? 0, privacy: .public)")
        phaseByVideoID[video.id] = "video"
        try await downloadStream(from: videoURL, to: videoFile, videoID: video.id, snapshotID: snapshotID, title: video.title)
        phaseByVideoID[video.id] = "audio"
        try await downloadStream(from: audioURL, to: audioFile, videoID: video.id, snapshotID: snapshotID, title: video.title)
        phaseByVideoID[video.id] = "muxing"

        try await muxToDestination(video: videoFile, audio: audioFile, destination: destination)
    }

    /// Two-tier format fetch for the fallback path.
    ///
    /// 1. **`fetchInfoViaTVHTML5`** — uses `YouTubeKitClient.tvHtmlModel` (TVHTML5_SIMPLY_
    ///    EMBEDDED_PLAYER context). PoT-exempt on the video-info side. Cheap: one HTTP call, no
    ///    player-JS scrape. Caveat: the response carries `signatureCipher`-protected URLs for
    ///    some videos and YouTubeKit drops those (no JS runtime to decode them on iOS), so on
    ///    cipher-heavy content we get back zero formats.
    ///
    /// 2. **`fetchInfoWithFormats`** — uses `VideoInfosWithDownloadFormatsResponse`, which
    ///    additionally scrapes the YouTube player.js and decodes signature ciphers natively
    ///    in YouTubeKit. Slower (two HTTP calls + JS parsing) but produces direct URLs even
    ///    for cipher-protected formats. Falls through to this tier when TVHTML5 returned
    ///    nothing usable — exactly the case the Baby-Shark video hit.
    ///
    /// Either tier failing silently returns an empty array; the caller treats that as "no
    /// fallback path available" and surfaces `streamExtractionFailed`.
    private func fetchFallbackFormats(videoID: String) async -> [VideoFormat] {
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

    /// Downloads a single direct stream with a file-backed URLSession task. The previous
    /// `AsyncBytes` loop suspended once per byte and capped an 18 MB audio file near 32 KB/s.
    /// Progress still feeds the existing snapshot pipeline; final size and media validation stay
    /// unchanged.
    private func downloadStream(
        from url: URL,
        to destination: URL,
        videoID: String,
        snapshotID: String,
        title: String,
        sendTVClientUserAgent: Bool = true,
        sourceLabel: String = "fallback"
    ) async throws {
        try? FileManager.default.removeItem(at: destination)
        var request = URLRequest(url: url)
        if sendTVClientUserAgent {
            // Match the TVHTML5_SIMPLY_EMBEDDED_PLAYER user-agent we set on `tvHtmlModel`.
            // The CDN occasionally rejects requests whose UA doesn't match the client that
            // minted the URL. Native progressive audio uses URLSession's normal agent instead.
            request.setValue("Mozilla/5.0 (PlayStation; PlayStation 4/12.55) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }

        // Googlevideo sometimes omits Content-Length while retaining its `clen` parameter.
        // Use it for progress only; never persist or log the signed URL itself.
        let declaredLength = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "clen" })?.value.flatMap(Int64.init)
        let startedAt = Date()
        let reportProgress: @Sendable (Int64, Int64) -> Void = { [weak self] written, total in
            Task { @MainActor [weak self] in
                guard let self,
                      let snapshot = self.tasks[snapshotID],
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

        // The same signed audio URL took ~32 KB/s as one long response in device logs. Use a
        // small Range probe and at most four concurrent chunks for native audio; if the server
        // ignores ranges or any chunk fails, the existing single-request path remains intact.
        var usedRanges = false
        if sourceLabel == "native-audio", let declaredLength, declaredLength > 64 * 1024 {
            do {
                usedRanges = try await RangedMediaDownloadService.download(
                    request: request, to: destination, totalBytes: declaredLength,
                    onProgress: reportProgress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.notice("[native-audio] range transfer failed; retrying as one request: \(String(describing: error), privacy: .public)")
                try? FileManager.default.removeItem(at: destination)
            }
        }

        let http: HTTPURLResponse?
        if usedRanges {
            http = nil
        } else {
            http = try await DirectFileDownloadService.download(
                request: request,
                to: destination,
                expectedSizeHint: declaredLength,
                onProgress: reportProgress
            )
        }
        if let http, !(200..<300).contains(http.statusCode) {
            log.error("[\(sourceLabel, privacy: .public)] HTTP \(http.statusCode, privacy: .public) from \(url.host ?? "?", privacy: .public)\(url.path, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
        let expected = usedRanges ? (declaredLength ?? -1) : (http?.expectedContentLength ?? -1)
        let written = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        log.info("[\(sourceLabel, privacy: .public)] wrote \(written, privacy: .public) bytes in \(Date().timeIntervalSince(startedAt), privacy: .public)s mode=\(usedRanges ? "ranges" : "single", privacy: .public) to \(destination.lastPathComponent, privacy: .public)")

        guard written >= Self.minimumDownloadSize else {
            log.error("[\(sourceLabel, privacy: .public)] refusing undersized stream: wrote=\(written, privacy: .public) bytes")
            try? FileManager.default.removeItem(at: destination)
            throw YouTubeServiceError.streamExtractionFailed
        }
        if expected > 0, written != expected {
            log.error("[\(sourceLabel, privacy: .public)] incomplete stream: wrote=\(written, privacy: .public) expected=\(expected, privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            throw YouTubeServiceError.streamExtractionFailed
        }
    }

    /// An explicit 1440p/2160p request gets first chance at separate native MP4/M4A streams.
    /// A playable HLS master can have a lower ceiling, so accepting it first would silently
    /// prevent a higher-resolution download even when a paired stream is available. Ordinary
    /// downloads retain the faster HLS-first path; failure here falls back to that same path.
    private func resolveNativeDownloadSource(video: Video, quality: VideoQuality) async throws -> NativeStreamResult {
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

    /// Materializes the native source used by playback. HLS, direct MP4, and separate MP4/M4A
    /// streams have distinct transfer paths; treating a video-only URL as a complete file would
    /// fail final validation and needlessly invoke the embedded Python fallback.
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
                throw YouTubeServiceError.streamExtractionFailed
            }
            guard !audioOnly else { throw YouTubeServiceError.streamExtractionFailed }
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
                sendTVClientUserAgent: false, sourceLabel: "native-video"
            )
            try Task.checkCancellation()
            phaseByVideoID[video.id] = "audio"
            try await downloadStream(
                from: audioURL, to: temporaryAudio, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                sendTVClientUserAgent: false, sourceLabel: "native-audio"
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
            guard exit == 0 else { throw YouTubeServiceError.streamExtractionFailed }
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
                sendTVClientUserAgent: false,
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
            guard exit == 0 else { throw YouTubeServiceError.streamExtractionFailed }
            return
        }

        if source.mediaKind == .direct {
            phaseByVideoID[video.id] = "stream"
            try await downloadStream(
                from: source.url, to: destination, videoID: video.id,
                snapshotID: snapshotID, title: video.title,
                sendTVClientUserAgent: false, sourceLabel: "native-video"
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

    /// A filesystem path alone is not proof that a download succeeded. yt-dlp and URLSession can
    /// both leave a zero-byte or truncated file behind after a CDN rejection, and historically that
    /// made the UI announce “Download finished” before the Downloads screen failed to open it.
    /// Validate the finished asset before writing metadata or publishing `.completed`.
    private func validateDownloadedFile(at url: URL, quality: VideoQuality, videoID: String) async throws {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= Self.minimumDownloadSize else {
            log.error("yt-dlp[\(videoID, privacy: .public)] validation: output missing or smaller than \(Self.minimumDownloadSize, privacy: .public) bytes")
            throw YouTubeServiceError.streamExtractionFailed
        }

        let asset = AVURLAsset(url: url)
        do {
            async let playableTask = asset.load(.isPlayable)
            async let durationTask = asset.load(.duration)
            async let videoTracksTask = asset.loadTracks(withMediaType: .video)
            async let audioTracksTask = asset.loadTracks(withMediaType: .audio)
            let (playable, duration, videoTracks, audioTracks) = try await (
                playableTask, durationTask, videoTracksTask, audioTracksTask
            )
            let seconds = duration.seconds
            let hasExpectedTracks = quality == .audioOnly
                ? !audioTracks.isEmpty
                : !videoTracks.isEmpty && !audioTracks.isEmpty
            guard playable, seconds.isFinite, seconds > 0, hasExpectedTracks else {
                log.error("yt-dlp[\(videoID, privacy: .public)] validation: playable=\(playable, privacy: .public) duration=\(seconds, privacy: .public) videoTracks=\(videoTracks.count, privacy: .public) audioTracks=\(audioTracks.count, privacy: .public)")
                throw YouTubeServiceError.streamExtractionFailed
            }
            if let videoTrack = videoTracks.first,
               let size = try? await videoTrack.load(.naturalSize),
               size.width.isFinite, size.height.isFinite,
               abs(size.width) < 100_000, abs(size.height) < 100_000 {
                log.info("yt-dlp[\(videoID, privacy: .public)] output video dimensions=\(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public)")
            }
            log.info("yt-dlp[\(videoID, privacy: .public)] validation passed: size=\(size.int64Value, privacy: .public) duration=\(seconds, privacy: .public)s videoTracks=\(videoTracks.count, privacy: .public) audioTracks=\(audioTracks.count, privacy: .public)")
        } catch {
            log.error("yt-dlp[\(videoID, privacy: .public)] validation could not read asset: \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }

    // MARK: - Muxing (direct ffmpeg call, no Python)

    /// Combines a video-only mp4 with an audio-only m4a into a single mp4 using `ffmpeg -c copy`.
    ///
    /// **Why ffmpeg:** yt-dlp delivers YouTube's DASH-fragmented mp4. AVFoundation parses these
    /// containers with halved frame rate (per-frame PTS values in the fragmented mp4 read as 2× the
    /// real values), so any AVAssetExportSession/AVAssetReader-based mux produces a doubled-duration
    /// output. `ffmpeg -c copy` is the canonical fixup — it rewrites the moov atom into a regular
    /// (non-fragmented) mp4 with correct timestamps without re-encoding.
    ///
    /// **Why not via yt-dlp's Popen:** the previous hang we hit was Python's `Popen.communicate`
    /// never returning after ffmpeg's `longjmp` tore through the Python interpreter's stack. Calling
    /// `FFmpegSupport.ffmpeg(_:)` *directly* from Swift sidesteps Python entirely — the longjmp
    /// lands at the C `setjmp` inside the library and control returns to Swift cleanly.
    private func muxToDestination(video: URL, audio: URL, destination: URL) async throws {
        log.info("mux via ffmpeg: video=\(video.lastPathComponent, privacy: .public) audio=\(audio.lastPathComponent, privacy: .public)")
        try? FileManager.default.removeItem(at: destination)

        let args: [String] = [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel", "warning",
            "-i", video.path,
            "-i", audio.path,
            "-c", "copy",
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-movflags", "+faststart",
            destination.path
        ]
        log.info("ffmpeg argv: \(args.joined(separator: " "), privacy: .public)")

        let startedAt = Date()
        // Route every ffmpeg invocation through the shared `FFmpegRunner` actor. ffmpeg's C
        // library is **not** thread-safe — the `+faststart` post-pass crashes on concurrent
        // calls (see FFmpegRunner doc comment). Plain `Task.detached` here was the bug: each
        // parallel playlist download finishing its yt-dlp step fired its own ffmpeg detach,
        // and two of them stomping global buffers blew up inside `ff_format_shift_data`.
        let exitCode = await FFmpegRunner.shared.run(args)
        let elapsed = Date().timeIntervalSince(startedAt)
        log.info("ffmpeg returned exit=\(exitCode, privacy: .public) in \(String(format: "%.1f", elapsed), privacy: .public)s")

        guard exitCode == 0 else {
            log.error("ffmpeg failed exit=\(exitCode, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            log.error("ffmpeg returned 0 but output missing at \(destination.path, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }

        // Sanity-log the final duration so any future regression is obvious in os_log.
        let asset = AVURLAsset(url: destination)
        if let dur = try? await asset.load(.duration) {
            log.info("ffmpeg-muxed file duration=\(dur.seconds, privacy: .public)s path=\(destination.lastPathComponent, privacy: .public)")
        }
    }
    // MARK: - File locations + format selection

    /// Canonical on-disk location for a downloaded video. Files land at the **Documents
    /// root** so they're visible in the system Files app under "On My iPhone" /
    /// "On My iPad" (gated by `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`
    /// in Info.plist). Every video gets a fixed `mp4` extension because yt-dlp's merger
    /// produces an mp4 container.
    static func fileURL(for videoID: String) -> URL {
        downloadsDirectory.appendingPathComponent("\(videoID).mp4")
    }

    /// Resolve Documents once, before embedded Python can alter process-level path state.
    /// Re-evaluating `.documentDirectory` after Python initialization produced a path with an
    /// obsolete app-container Documents directory appended inside the current container.
    private static let downloadsDirectory = AppDirectories.documents

    /// Reject placeholder/error-response files while still allowing very short clips.
    private static let minimumDownloadSize: Int64 = 64 * 1_024

    // MARK: - Networking gate + snapshots

    private func startMonitoringPath() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in self.currentPath = path }
        }
        pathMonitor.start(queue: DispatchQueue(label: "DownloadManager.path"))
    }

    private func waitForAllowedNetwork() async throws {
        // Permissive default: if the user allows cellular, never block.
        if preferences.allowCellularDownloads { return }
        let path = currentPath ?? pathMonitor.currentPath
        if path.usesInterfaceType(.wifi) { return }
        throw YouTubeServiceError.network(NSError(
            domain: "FreeTube.DownloadManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Cellular downloads are disabled in Settings, but Wi-Fi isn't currently available."]
        ))
    }

    private func publish(snapshot: DownloadTaskSnapshot) {
        // Progress callbacks already queued on the main actor can outlive cancellation.
        guard !cancelledSnapshotIDs.contains(snapshot.id) else { return }
        var snapshot = snapshot
        if !snapshot.id.hasPrefix("fetch-"), case .downloading(let raw) = snapshot.state {
            var tracker = overallProgress[snapshot.id] ?? DownloadOverallProgress()
            let value = tracker.update(raw, phase: phaseByVideoID[snapshot.videoID] ?? "stream")
            overallProgress[snapshot.id] = tracker
            snapshot = DownloadTaskSnapshot(
                id: snapshot.id, videoID: snapshot.videoID, title: snapshot.title,
                state: .downloading(progress: value), createdAt: snapshot.createdAt
            )
        }
        tasks[snapshot.id] = snapshot
        if case .downloading(let value) = snapshot.state {
            progressByVideoID[snapshot.videoID] = value
        } else if case .completed = snapshot.state {
            overallProgress[snapshot.id] = nil
            progressByVideoID.removeValue(forKey: snapshot.videoID)
            retryRequests[snapshot.id] = nil
        } else if case .failed = snapshot.state {
            overallProgress[snapshot.id] = nil
            progressByVideoID.removeValue(forKey: snapshot.videoID)
        }
        publishSnapshots()
    }

    private func publishSnapshots() {
        activeTasks = Array(tasks.values).sorted { $0.createdAt > $1.createdAt }
        log.debug("publishSnapshots: \(self.activeTasks.count, privacy: .public) entries")
    }
}
