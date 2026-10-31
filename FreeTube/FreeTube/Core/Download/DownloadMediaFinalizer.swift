import AVFoundation
import Foundation
import OSLog

/// Validates completed downloads and combines separate video and audio tracks. All download
/// sources use the same checks before the manager publishes a file as completed.
@available(iOS 17.0, *)
@MainActor
final class DownloadMediaFinalizer {
    static let minimumFileSize: Int64 = 64 * 1_024

    private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")

    /// A filesystem path alone is not proof that a download succeeded. CDN rejections can leave
    /// undersized or unplayable files behind, so validate before writing metadata.
    func validateFile(at url: URL, quality: VideoQuality, videoID: String) async throws {
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= Self.minimumFileSize else {
            log.error("yt-dlp[\(videoID, privacy: .public)] validation: output missing or smaller than \(Self.minimumFileSize, privacy: .public) bytes")
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

    /// Remux DASH video and audio without re-encoding. AVFoundation can misread timestamps in
    /// YouTube's fragmented MP4 tracks and produce an incorrect duration when it exports them.
    /// FFmpeg rewrites the container timestamps, and FFmpegRunner serializes access to its
    /// process-wide C state because concurrent runs can crash during the fast-start pass.
    func mux(video: URL, audio: URL, destination: URL) async throws {
        log.info("mux via ffmpeg: video=\(video.lastPathComponent, privacy: .public) audio=\(audio.lastPathComponent, privacy: .public)")
        try? FileManager.default.removeItem(at: destination)

        let args: [String] = [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
            "-i", video.path, "-i", audio.path,
            "-c", "copy", "-map", "0:v:0", "-map", "1:a:0",
            "-movflags", "+faststart", destination.path
        ]
        log.info("ffmpeg argv: \(args.joined(separator: " "), privacy: .public)")

        let startedAt = Date()
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

        let asset = AVURLAsset(url: destination)
        if let duration = try? await asset.load(.duration) {
            log.info("ffmpeg-muxed file duration=\(duration.seconds, privacy: .public)s path=\(destination.lastPathComponent, privacy: .public)")
        }
    }
}
