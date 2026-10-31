import AVFoundation
import Foundation
import OSLog

/// Resolves and probes a high-speed source without touching the visible AVQueuePlayer.
/// The caller owns the item handoff and the returned temporary file after this succeeds.
@available(iOS 17.0, *)
@MainActor
final class PlayerFastPlaybackCandidatePreparer {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")

    func prepare(
        video: Video,
        quality: VideoQuality,
        referenceDuration: TimeInterval,
        resolver: any PlaybackResolving,
        itemFactory: PlaybackItemFactory,
        onCompositePreparation: @escaping @MainActor () -> Void,
        onProgress: @escaping FastPlaybackLocalFileService.ProgressHandler
    ) async throws -> (item: AVPlayerItem, temporaryFile: URL?) {
        let candidate = try await resolver.resolveForFastPlayback(video: video, quality: quality)
        try Task.checkCancellation()

        var temporaryFile: URL?
        var succeeded = false
        defer {
            if !succeeded, let temporaryFile {
                FastPlaybackLocalFileService.remove(temporaryFile)
            }
        }

        let itemToProbe: AVPlayerItem
        switch candidate.source {
        case .direct, .localFile:
            itemToProbe = try await itemFactory.makeItem(for: candidate)
        case .composite(let videoURL, let audioURL):
            // Remote AVCompositions stalled on device. Keep the working stream playing while
            // the paired tracks are materialized into a cancellable temporary file.
            onCompositePreparation()
            log.info("Preparing temporary local file for fast playback of \(video.id, privacy: .public): workingDuration=\(referenceDuration, privacy: .public)s videoMetadataDuration=\(video.duration ?? -1, privacy: .public)s")
            let file = try await FastPlaybackLocalFileService.prepare(
                videoURL: videoURL,
                audioURL: audioURL,
                referenceDuration: referenceDuration,
                onProgress: onProgress
            )
            temporaryFile = file
            itemToProbe = AVPlayerItem(url: file)
        }
        try Task.checkCancellation()
        let preparation = FastPlaybackPreparation(item: itemToProbe)
        let preparedAsset = try await preparation.prepare(audioOnly: quality == .audioOnly)
        try Task.checkCancellation()
        // Never adopt the probe's AVPlayerItem: a separate item made from its prepared asset
        // avoids AVFoundation associating one item with two players during detachment.
        let replacement = AVPlayerItem(asset: preparedAsset)
        replacement.audioTimePitchAlgorithm = .timeDomain
        succeeded = true
        return (replacement, temporaryFile)
    }
}
