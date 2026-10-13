import Foundation
import AVFoundation
import OSLog

/// Turns a resolved source into an AVPlayerItem without installing it in a player.
/// In particular, a paired source is composed in memory; this reads remote track metadata but
/// does not save media or signed URLs. Item ownership and validation remain with PlayerStateManager.
@available(iOS 17.0, *)
@MainActor
struct PlaybackItemFactory {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlaybackItemFactory")

    /// Extensionless remote audio URLs need their actual container type. A selected HLS audio
    /// rendition is a playlist, not an MP4, so source MIME overrides must travel with candidates.
    func makeItem(for candidate: PlaybackCandidate) async throws -> AVPlayerItem {
        if case .composite(let videoURL, let audioURL) = candidate.source {
            // AVMutableComposition references both remote tracks. It does not mux or persist a
            // file. Extensionless signed URLs need their actual media types.
            let videoAsset = AVURLAsset(url: videoURL, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
            let audioAsset = AVURLAsset(url: audioURL, options: [AVURLAssetOverrideMIMETypeKey: "audio/mp4"])
            var stage = "video-track"
            do {
                guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
                    throw YouTubeServiceError.streamExtractionFailed
                }
                stage = "audio-track"
                guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                    throw YouTubeServiceError.streamExtractionFailed
                }
                stage = "video-duration"
                let videoDuration = try await videoAsset.load(.duration)
                stage = "audio-duration"
                let audioDuration = try await audioAsset.load(.duration)
                stage = "duration-validation"
                guard videoDuration.isValid, audioDuration.isValid,
                      videoDuration.seconds.isFinite, audioDuration.seconds.isFinite,
                      videoDuration.seconds > 0, audioDuration.seconds > 0 else {
                    throw YouTubeServiceError.streamExtractionFailed
                }
                let audioEnd = CMTimeCompare(videoDuration, audioDuration) <= 0 ? videoDuration : audioDuration
                let composition = AVMutableComposition()
                stage = "composition-tracks"
                guard let compositionVideo = composition.addMutableTrack(
                    withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
                ), let compositionAudio = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw YouTubeServiceError.streamExtractionFailed
                }
                stage = "video-insertion"
                try compositionVideo.insertTimeRange(
                    CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero
                )
                stage = "audio-insertion"
                try compositionAudio.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioEnd), of: audioTrack, at: .zero
                )
                stage = "preferred-transform"
                compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
                stage = "composition-copy"
                guard let playbackComposition = composition.copy() as? AVComposition else {
                    throw YouTubeServiceError.streamExtractionFailed
                }
                log.info("Prepared paired video/audio composition duration=\(videoDuration.seconds, privacy: .public)s")
                return AVPlayerItem(asset: playbackComposition)
            } catch {
                let nsError = error as NSError
                log.notice("Paired source preparation failed stage=\(stage, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
                if stage == "video-track" {
                    // Probe only the response and first byte after AVFoundation rejects the URL.
                    // Never log the signed URL or delay the resolver's next candidate.
                    Task { [videoURL] in
                        await self.diagnoseRemoteVideoTrack(videoURL)
                    }
                }
                throw error
            }
        }
        guard case .direct(let url) = candidate.source,
              let mimeType = candidate.mimeTypeOverride else {
            return AVPlayerItem(url: candidate.source.url)
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mimeType])
        log.info("Remote candidate MIME override=\(mimeType, privacy: .public)")
        return AVPlayerItem(asset: asset)
    }

    private func diagnoseRemoteVideoTrack(_ url: URL) async {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 5
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            var iterator = bytes.makeAsyncIterator()
            let firstByte = try await iterator.next()
            let http = response as? HTTPURLResponse
            log.notice("Paired video HTTP probe status=\(http?.statusCode ?? 0, privacy: .public) mime=\(response.mimeType ?? "unknown", privacy: .public) range=\(http?.value(forHTTPHeaderField: "Content-Range") != nil, privacy: .public) length=\(response.expectedContentLength, privacy: .public) body=\(firstByte != nil, privacy: .public)")
        } catch {
            let nsError = error as NSError
            log.notice("Paired video HTTP probe failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }
    }
}
