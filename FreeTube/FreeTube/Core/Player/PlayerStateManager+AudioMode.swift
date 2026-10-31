import AVFoundation
import Foundation
import OSLog

/// Quality selection and audio-only source switching for the shared player.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Quality preference

    /// Updates the HLS adaptive-quality ceiling in place and persists it for future resolutions.
    /// Fixed progressive/local assets cannot switch representation after loading, but retain the
    /// new preference for the next video without disrupting current playback.
    func setPlaybackQuality(_ quality: VideoQuality) {
        guard quality != playbackQuality, !fastPlayback.isInstalling else { return }
        cancelFastPlaybackPreparation()
        fastPlayback.failed = false
        log.info("setPlaybackQuality(\(quality.rawValue, privacy: .public))")
        playbackQuality = quality
        if quality != .audioOnly { videoQualityBeforeAudio = quality }
        preferences.preferredQuality = quality
        if let item = player.currentItem {
            applyQualityCap(to: item)
        }
        reconcilePlaybackRate()
    }

    /// Re-resolve only the media source. The queue, active playlist, recommendations, chapters,
    /// and current presentation all stay in place. Resolution runs while the old item keeps
    /// playing; we replace it only once a candidate URL is available.
    // MARK: - Source switching

    func toggleAudioOnly() {
        guard !isSwitchingAudioMode, !isPreparingFastPlayback,
              loadState == .readyToPlay,
              let video = currentVideo,
              !video.id.hasPrefix("fetch-"),
              !video.isLive,
              !hasEnded,
              player.currentItem != nil else { return }

        let target: VideoQuality = isAudioOnly ? videoQualityBeforeAudio : .audioOnly
        isSwitchingAudioMode = true
        audioModeSwitchGeneration &+= 1
        let generation = audioModeSwitchGeneration
        audioModeSwitchTask = Task { [weak self] in
            await self?.switchPlaybackSource(for: video, to: target, generation: generation)
        }
    }

    private func switchPlaybackSource(for video: Video, to quality: VideoQuality, generation: Int) async {
        defer {
            if audioModeSwitchGeneration == generation {
                isSwitchingAudioMode = false
                resumeAfterAudioSwitch = nil
                audioModeSwitchTask = nil
                if !Task.isCancelled, currentVideo?.id == video.id, loadState == .readyToPlay {
                    reconcilePlaybackRate()
                }
            }
        }
        let candidate: PlaybackCandidate
        do {
            candidate = try await resolver.resolve(video: video, quality: quality, excluding: [])
        } catch {
            if !Task.isCancelled {
                log.notice("Audio mode switch resolution failed for \(video.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return
        }
        guard !Task.isCancelled,
              currentVideo?.id == video.id,
              let previousItem = player.currentItem else { return }

        let previousSize = videoPresentationSize
        let wasPlaying = isPlaying
        let currentTime = player.currentTime().seconds
        let position = currentTime.isFinite && currentTime >= 0 ? currentTime : elapsed
        let replacement: AVPlayerItem
        do {
            replacement = try await itemFactory.makeItem(for: candidate)
        } catch {
            log.notice("Audio mode switch candidate could not be prepared: \(PlayerItemReadinessGate.describe(itemError: error), privacy: .public)")
            return
        }
        guard !Task.isCancelled, audioModeSwitchGeneration == generation,
              currentVideo?.id == video.id, player.currentItem === previousItem else { return }
        applyQualityCap(to: replacement, quality: quality)
        pause()
        resumeAfterAudioSwitch = wasPlaying
        pendingSeekTarget = position
        seekRequestID += 1
        loadState = .buffering
        itemLoadStartedAt = Date()
        loadItem(replacement, originalAudioLanguageCode: candidate.originalAudioLanguageCode)
        let readiness = await readinessGate.wait(
            for: replacement,
            timeout: readinessTimeout(for: candidate.strategy)
        )
        guard !Task.isCancelled,
              currentVideo?.id == video.id,
              player.currentItem === replacement else { return }

        switch readiness {
        case .ready:
            let previousQuality = playbackQuality
            playbackQuality = quality
            if quality == .audioOnly { videoQualityBeforeAudio = previousQuality }
            preferences.preferredQuality = quality
            if quality == .audioOnly { videoPresentationSize = .zero }
            await seekForSourceSwitch(to: pendingSeekTarget ?? position, item: replacement)
            guard !Task.isCancelled, currentVideo?.id == video.id,
                  player.currentItem === replacement else { return }
            guard replacement.status == .readyToPlay else {
                await restoreSourceAfterFailedSwitch(
                    previousItem, videoID: video.id, position: position, size: previousSize
                )
                return
            }
            pendingSeekTarget = nil
            acceptedStreamItem = replacement
            acceptedStreamStrategy = candidate.strategy
            loadState = .readyToPlay
            if resumeAfterAudioSwitch == true { play() }
            updateNowPlaying()
            fastPlayback.failed = false
            log.info("Audio mode switch succeeded for \(video.id, privacy: .public) audioOnly=\(quality == .audioOnly, privacy: .public)")
        case .failed(let reason):
            log.notice("Audio mode switch rejected for \(video.id, privacy: .public): \(reason, privacy: .public)")
            await restoreSourceAfterFailedSwitch(
                previousItem, videoID: video.id, position: position, size: previousSize
            )
        case .timedOut:
            log.notice("Audio mode switch timed out for \(video.id, privacy: .public) itemStatus=\(replacement.status.rawValue, privacy: .public) playerTimeControl=\(self.player.timeControlStatus.rawValue, privacy: .public)")
            await restoreSourceAfterFailedSwitch(
                previousItem, videoID: video.id, position: position, size: previousSize
            )
        }
    }

    private func restoreSourceAfterFailedSwitch(
        _ item: AVPlayerItem,
        videoID: String,
        position: TimeInterval,
        size: CGSize
    ) async {
        loadItem(item)
        videoPresentationSize = size
        await seekForSourceSwitch(to: pendingSeekTarget ?? position, item: item)
        guard !Task.isCancelled, currentVideo?.id == videoID,
              player.currentItem === item else { return }
        pendingSeekTarget = nil
        loadState = .readyToPlay
        if resumeAfterAudioSwitch == true { play() }
        updateNowPlaying()
    }

    func seekForSourceSwitch(to seconds: TimeInterval, item: AVPlayerItem) async {
        let itemDuration = item.duration.seconds
        let position = itemDuration.isFinite && itemDuration > 0
            ? min(seconds, max(0, itemDuration - 0.25)) : seconds
        let time = CMTime(seconds: max(0, position), preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        guard player.currentItem === item else { return }
        elapsed = position
    }

}
