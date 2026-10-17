import AVFoundation
import Foundation
import OSLog

/// Materializes separate, short-lived video/audio URLs into one local MP4 for fast playback.
/// Ordinary playback never calls this service. Work lives in the app's temporary directory and
/// is cancelled with the requesting task; only a successfully validated file is handed back.
@available(iOS 17.0, *)
@MainActor
final class FastPlaybackLocalFileService {
    enum Phase: String, Sendable {
        case resolving = "Finding streams"
        case video = "Downloading video"
        case audio = "Downloading audio"
        case finishing = "Finishing"
    }

    enum Failure: Error {
        case insufficientSpace
        case invalidResponse(Int)
        case missingTracks
        case timelineMismatch
        case missingPlayableTail
        case exportUnavailable
        case exportFailed
    }

    struct ProgressUpdate: Sendable {
        let phase: Phase
        let completedBytes: Int64
        let totalBytes: Int64?

        var fraction: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
        }
    }

    typealias ProgressHandler = @MainActor @Sendable (ProgressUpdate) -> Void

    /// The indicator has one byte counter for the complete video + audio transfer. `clen`
    /// can supply both sizes before either transfer starts; if it does not, the indicator
    /// stays indeterminate until the second size is known rather than showing a false percentage.
    @MainActor
    private final class ProgressAccumulator {
        private let onProgress: ProgressHandler
        private var videoBytes: Int64 = 0
        private var audioBytes: Int64 = 0
        private var expectedVideoBytes: Int64?
        private var expectedAudioBytes: Int64?
        private var videoDone = false
        private var audioDone = false

        init(videoURL: URL, audioURL: URL, onProgress: @escaping ProgressHandler) {
            self.onProgress = onProgress
            expectedVideoBytes = FastPlaybackLocalFileService.declaredSize(of: videoURL)
            expectedAudioBytes = FastPlaybackLocalFileService.declaredSize(of: audioURL)
        }

        func report(_ phase: Phase, written: Int64, expected: Int64?) {
            switch phase {
            case .video:
                guard !videoDone else { return }
                videoBytes = max(videoBytes, written)
                if let expected, expected > 0 { expectedVideoBytes = expected }
            case .audio:
                guard !audioDone else { return }
                audioBytes = max(audioBytes, written)
                if let expected, expected > 0 { expectedAudioBytes = expected }
            case .resolving, .finishing:
                break
            }
            emit(phase)
        }

        func completed(_ phase: Phase, bytes: Int64) {
            switch phase {
            case .video:
                videoDone = true
                videoBytes = bytes
                expectedVideoBytes = bytes
            case .audio:
                audioDone = true
                audioBytes = bytes
                expectedAudioBytes = bytes
            case .resolving, .finishing:
                break
            }
            emit(phase)
        }

        func emit(_ phase: Phase) {
            let total: Int64?
            if let expectedVideoBytes, let expectedAudioBytes,
               expectedVideoBytes <= Int64.max - expectedAudioBytes {
                total = expectedVideoBytes + expectedAudioBytes
            } else {
                total = nil
            }
            onProgress(ProgressUpdate(
                phase: phase,
                completedBytes: videoBytes + audioBytes,
                totalBytes: total
            ))
        }
    }

    /// Keep enough space for both input files and their exported copy. This is a per-request
    /// ceiling, not a persistent cache: iOS may remove temporary files after app termination.
    private static let maximumMediaBytes: Int64 = 1_000_000_000
    private static let reservedBytes: Int64 = 200_000_000
    private static let log = AppLog(subsystem: "com.leshko.freetube", category: "FastPlaybackLocalFileService")
    private static let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FreeTubeFastPlayback", isDirectory: true)
    private static var removedOrphansThisLaunch = false

    static func removeOrphansAtLaunch() {
        guard !removedOrphansThisLaunch else { return }
        removedOrphansThisLaunch = true
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) else { return }
        let orphans = children.filter { UUID(uuidString: $0.lastPathComponent) != nil }
        guard !orphans.isEmpty else { return }
        Task.detached(priority: .utility) {
            for directory in orphans {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    static func prepare(
        videoURL: URL,
        audioURL: URL,
        referenceDuration: TimeInterval?,
        onProgress: @escaping ProgressHandler
    ) async throws -> URL {
        try Task.checkCancellation()
        let progress = ProgressAccumulator(
            videoURL: videoURL, audioURL: audioURL, onProgress: onProgress
        )
        progress.emit(.video)
        let startedAt = Date()
        let workDirectory = rootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let videoFile = workDirectory.appendingPathComponent("video.mp4")
        let audioFile = workDirectory.appendingPathComponent("audio.m4a")
        let outputFile = workDirectory.appendingPathComponent("playback.mp4")
        var completed = false
        defer {
            try? FileManager.default.removeItem(at: videoFile)
            try? FileManager.default.removeItem(at: audioFile)
            if !completed { try? FileManager.default.removeItem(at: workDirectory) }
        }

        let available = (try? workDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ))?.volumeAvailableCapacityForImportantUsage
        let capacityLimit = available.map { max(0, ($0 - reservedBytes) / 2) } ?? maximumMediaBytes
        let mediaLimit = min(maximumMediaBytes, capacityLimit)
        guard mediaLimit >= 50_000_000 else { throw Failure.insufficientSpace }
        log.info("Fast playback temporary preparation started, combined input limit=\(mediaLimit, privacy: .public) bytes")

        try await transfer(
            videoURL, to: videoFile, maximumBytes: mediaLimit,
            phase: .video, progress: progress
        )
        try Task.checkCancellation()
        let videoBytes = try fileSize(at: videoFile)
        guard videoBytes < mediaLimit else { throw Failure.insufficientSpace }
        try await transfer(
            audioURL, to: audioFile, maximumBytes: mediaLimit - videoBytes,
            phase: .audio, progress: progress
        )
        try Task.checkCancellation()

        progress.emit(.finishing)
        let videoAsset = AVURLAsset(url: videoFile)
        let audioAsset = AVURLAsset(url: audioFile)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw Failure.missingTracks
        }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard videoDuration.isValid, audioDuration.isValid,
              videoDuration.seconds.isFinite, audioDuration.seconds.isFinite,
              videoDuration.seconds > 0, audioDuration.seconds > 0 else {
            throw Failure.missingTracks
        }
        log.info("Fast playback source durations: video=\(videoDuration.seconds, privacy: .public)s audio=\(audioDuration.seconds, privacy: .public)s")
        let videoRange = try await videoTrack.load(.timeRange)
        let audioRange = try await audioTrack.load(.timeRange)
        let videoHint = durationHint(of: videoURL)
        let audioHint = durationHint(of: audioURL)
        log.info("Fast playback source timing: videoTrack=\(videoRange.start.seconds, privacy: .public)..\(CMTimeRangeGetEnd(videoRange).seconds, privacy: .public)s audioTrack=\(audioRange.start.seconds, privacy: .public)..\(CMTimeRangeGetEnd(audioRange).seconds, privacy: .public)s URLDurations=\(videoHint ?? -1, privacy: .public)/\(audioHint ?? -1, privacy: .public)s")
        let sourceEnd = min(videoDuration.seconds, audioDuration.seconds)
        var videoEnd = videoDuration
        var audioEnd = audioDuration
        if let referenceDuration, referenceDuration.isFinite, referenceDuration > 10,
           abs(sourceEnd - referenceDuration) > max(2, referenceDuration * 0.05) {
            // YouTube's URLs and the working HLS item independently agree on the length,
            // while AVFoundation can report a doubled range for these adaptive files. Only
            // use the URL durations if both tracks are proven to end there; never blindly halve.
            guard let videoHint, let audioHint,
                  sourceEnd > referenceDuration * 1.8,
                  sourceEnd < referenceDuration * 2.2,
                  abs(videoHint - referenceDuration) <= max(2, referenceDuration * 0.02),
                  abs(audioHint - referenceDuration) <= max(2, referenceDuration * 0.02),
                  abs(videoDuration.seconds - videoHint * 2) <= max(2, videoHint * 0.02),
                  abs(audioDuration.seconds - audioHint * 2) <= max(2, audioHint * 0.02) else {
                log.notice("Fast playback timeline mismatch lacks matching source-duration evidence: reference=\(referenceDuration, privacy: .public)s source=\(sourceEnd, privacy: .public)s")
                throw Failure.timelineMismatch
            }
            let videoHasExtraSamples = try containsSamples(
                in: videoAsset, track: videoTrack,
                startingAt: videoHint + 1, endingAt: videoDuration.seconds
            )
            let audioHasExtraSamples = try containsSamples(
                in: audioAsset, track: audioTrack,
                startingAt: audioHint + 1, endingAt: audioDuration.seconds
            )
            let videoHasReferenceSamples = try containsSamples(
                in: videoAsset, track: videoTrack, endingAt: videoHint
            )
            let audioHasReferenceSamples = try containsSamples(
                in: audioAsset, track: audioTrack, endingAt: audioHint
            )
            log.notice("Fast playback timeline diagnostic: reference=\(referenceDuration, privacy: .public)s source=\(sourceEnd, privacy: .public)s nearReferenceVideo=\(videoHasReferenceSamples, privacy: .public) nearReferenceAudio=\(audioHasReferenceSamples, privacy: .public) afterReferenceVideo=\(videoHasExtraSamples, privacy: .public) afterReferenceAudio=\(audioHasExtraSamples, privacy: .public)")
            guard videoHasReferenceSamples, audioHasReferenceSamples,
                  !videoHasExtraSamples, !audioHasExtraSamples else {
                throw Failure.timelineMismatch
            }
            videoEnd = CMTime(seconds: videoHint, preferredTimescale: 600)
            audioEnd = CMTime(seconds: audioHint, preferredTimescale: 600)
            log.notice("Fast playback source timeline corrected using verified URL durations: video=\(videoHint, privacy: .public)s audio=\(audioHint, privacy: .public)s")
        }
        audioEnd = CMTimeCompare(videoEnd, audioEnd) <= 0 ? videoEnd : audioEnd
        try Task.checkCancellation()
        let composition = AVMutableComposition()
        guard let composedVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ), let composedAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw Failure.missingTracks
        }
        try composedVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoEnd), of: videoTrack, at: .zero
        )
        try composedAudio.insertTimeRange(
            CMTimeRange(start: .zero, duration: audioEnd), of: audioTrack, at: .zero
        )
        composedVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try Task.checkCancellation()
        guard let preparedComposition = composition.copy() as? AVComposition,
              let exporter = AVAssetExportSession(
                asset: preparedComposition, presetName: AVAssetExportPresetPassthrough
              ), exporter.supportedFileTypes.contains(.mp4) else {
            throw Failure.exportUnavailable
        }
        exporter.outputURL = outputFile
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = false
        try await export(exporter)
        try Task.checkCancellation()
        guard try fileSize(at: outputFile) > 1_024 else { throw Failure.exportFailed }
        let finalAsset = AVURLAsset(url: outputFile)
        let finalVideoTracks = try await finalAsset.loadTracks(withMediaType: .video)
        let finalAudioTracks = try await finalAsset.loadTracks(withMediaType: .audio)
        guard !finalVideoTracks.isEmpty, !finalAudioTracks.isEmpty else {
            throw Failure.missingTracks
        }
        let finalDuration = try await finalAsset.load(.duration)
        guard finalDuration.seconds.isFinite, finalDuration.seconds > 0 else {
            throw Failure.missingPlayableTail
        }
        if let referenceDuration, referenceDuration.isFinite, referenceDuration > 10,
           abs(finalDuration.seconds - referenceDuration) > max(2, referenceDuration * 0.05) {
            log.notice("Fast playback output timeline still differs: reference=\(referenceDuration, privacy: .public)s output=\(finalDuration.seconds, privacy: .public)s")
            throw Failure.timelineMismatch
        }
        let finalVideoHasTail = try containsSamples(
            in: finalAsset, track: finalVideoTracks[0], endingAt: finalDuration.seconds
        )
        let finalAudioHasTail = try containsSamples(
            in: finalAsset, track: finalAudioTracks[0], endingAt: finalDuration.seconds
        )
        log.info("Fast playback output tail probe: duration=\(finalDuration.seconds, privacy: .public)s video=\(finalVideoHasTail, privacy: .public) audio=\(finalAudioHasTail, privacy: .public)")
        guard finalVideoHasTail, finalAudioHasTail else { throw Failure.missingPlayableTail }
        log.info("Fast playback output tail validated at \(finalDuration.seconds, privacy: .public)s")
        let outputBytes = try fileSize(at: outputFile)
        log.info("Fast playback mux duration=\(finalDuration.seconds, privacy: .public)s")
        log.info("Fast playback temporary preparation completed: output=\(outputBytes, privacy: .public) bytes elapsed=\(Date().timeIntervalSince(startedAt), privacy: .public)s")
        completed = true
        return outputFile
    }

    static func remove(_ fileURL: URL) {
        let directory = fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().standardizedFileURL == rootDirectory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func transfer(
        _ source: URL,
        to destination: URL,
        maximumBytes: Int64,
        phase: Phase,
        progress: ProgressAccumulator
    ) async throws {
        var request = URLRequest(url: source)
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let declaredLength = declaredSize(of: source)
        if let declaredLength, declaredLength > maximumBytes {
            throw DirectFileDownloadService.Failure.sizeLimitExceeded
        }
        progress.emit(phase)
        let startedAt = Date()
        let reportProgress: @Sendable (Int64, Int64) -> Void = { written, expected in
            Task { @MainActor in
                progress.report(phase, written: written, expected: expected > 0 ? expected : nil)
            }
        }

        // A single long-lived media response can be paced close to playback speed. Use the
        // validated ranged transport for both tracks, retaining the single-request fallback.
        var usedRanges = false
        if let declaredLength, declaredLength > 64 * 1024 {
            do {
                usedRanges = try await RangedMediaDownloadService.download(
                    request: request, to: destination, totalBytes: declaredLength,
                    onProgress: reportProgress
                )
                if !usedRanges {
                    log.info("Fast playback \(phase.rawValue, privacy: .public) range probe unsupported; using one request")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("Fast playback \(phase.rawValue, privacy: .public) range transfer failed: \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public); retrying as one request")
                try? FileManager.default.removeItem(at: destination)
            }
        } else {
            log.info("Fast playback \(phase.rawValue, privacy: .public) has no usable declared length; using one request")
        }

        if !usedRanges {
            try Task.checkCancellation()
            let response = try await DirectFileDownloadService.download(
                request: request, to: destination,
                expectedSizeHint: declaredLength, maximumBytes: maximumBytes,
                onProgress: reportProgress
            )
            guard (200..<300).contains(response.statusCode) else {
                throw Failure.invalidResponse(response.statusCode)
            }
        }
        let transferredBytes = try fileSize(at: destination)
        if let declaredLength, transferredBytes != declaredLength {
            log.notice("Fast playback \(phase.rawValue, privacy: .public) declared \(declaredLength, privacy: .public) bytes but received \(transferredBytes, privacy: .public); validating media before use")
        }
        progress.completed(phase, bytes: transferredBytes)
        log.info("Fast playback \(phase.rawValue, privacy: .public) completed: \(transferredBytes, privacy: .public) bytes in \(Date().timeIntervalSince(startedAt), privacy: .public)s mode=\(usedRanges ? "ranges" : "single", privacy: .public)")
        try Task.checkCancellation()
    }

    private static func export(_ exporter: AVAssetExportSession) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    Task { @MainActor in
                        switch exporter.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing: exporter.error ?? Failure.exportFailed)
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in exporter.cancelExport() }
        }
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Reads only the non-secret duration field from a signed media URL; never log the URL.
    private static func durationHint(of url: URL) -> Double? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "dur" })?.value,
              let duration = Double(value), duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    /// Check actual compressed samples, not just container headers or a track's advertised range.
    /// A source with a long empty edit can report a valid duration and pass AVPlayer readiness,
    /// yet render black after its last video sample. A supplied start checks the whole remaining
    /// interval so trimming cannot silently discard media between the reference and file end.
    private static func containsSamples(
        in asset: AVAsset,
        track: AVAssetTrack,
        startingAt requestedStart: TimeInterval? = nil,
        endingAt end: TimeInterval
    ) throws -> Bool {
        guard end.isFinite, end > 0 else { return false }
        let start = requestedStart ?? max(0, end - min(4, end / 2))
        guard start.isFinite, start >= 0, start < end else { return false }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw Failure.missingPlayableTail }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        guard reader.startReading() else {
            throw reader.error ?? Failure.missingPlayableTail
        }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if CMSampleBufferGetNumSamples(sample) > 0,
               timestamp.isFinite, timestamp >= start - 0.1, timestamp <= end {
                return true
            }
        }
        if reader.status == .failed { throw reader.error ?? Failure.missingPlayableTail }
        return false
    }

    private static func declaredSize(of url: URL) -> Int64? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "clen" })?.value,
              let size = Int64(value), size > 0 else { return nil }
        return size
    }
}
