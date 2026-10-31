import AVFoundation
import Foundation
import OSLog

/// Fast playback commands and temporary-source handoff.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Rate selection

    func setPlaybackRate(_ rate: Double) {
        let boundedRate = fastPlayback.select(rate, isPreparing: isPreparingFastPlayback)
        log.info("Playback speed selected: \(boundedRate, privacy: .public)x")
        playbackRate = boundedRate
        // The player menu changes this video only. Settings owns the saved default; writing
        // menu choices there made subsequent HLS videos start at a capped 2x after a 3x choice.
        reconcilePlaybackRate()
        if let item = player.currentItem, item.status == .readyToPlay {
            log.info("Playback speed applied: selected=\(self.playbackRate, privacy: .public)x effective=\(self.effectivePlaybackRate, privacy: .public)x actual=\(self.player.rate, privacy: .public)x canPlayFastForward=\(item.canPlayFastForward, privacy: .public) pitch=\(item.audioTimePitchAlgorithm, privacy: .public)")
        }
    }

    /// Hold and menu speeds share the same capability checks and progressive-source experiment.
    /// Releasing a hold cancels unresolved work without changing the user's saved base speed.
    func beginTemporaryPlaybackRate(_ rate: Double) {
        guard !hasEnded,
              loadState == .readyToPlay,
              player.currentItem?.status == .readyToPlay,
              fastPlayback.beginTemporary(rate, wasPlaying: isPlaying) else { return }
        reconcilePlaybackRate()
        if !isPlaying { play() }
    }

    func endTemporaryPlaybackRate() {
        guard let restorePaused = fastPlayback.endTemporary() else { return }
        reconcilePlaybackRate()
        if restorePaused { pause() }
    }

    private var requestedTransportRate: Double { fastPlayback.requestedRate(baseRate: playbackRate) }

    /// Never send an unsupported HLS rate to AVPlayer. A paused, invisible probe prepares the
    /// alternative first, leaving the current video audible and seekable at up to 2x meanwhile.
    // MARK: - Preparation

    func reconcilePlaybackRate() {
        applyEffectivePlaybackRate()
        guard requestedTransportRate > 2 else {
            if !fastPlayback.isInstalling { cancelFastPlaybackPreparation() }
            return
        }
        // A hold must not start a potentially large temporary download. A saved high-speed
        // preference also waits for an explicit tap on each new online video.
        guard fastPlayback.temporaryRate == nil, fastPlayback.userRequested else { return }
        guard let item = player.currentItem, item.status == .readyToPlay,
              !item.canPlayFastForward, loadState == .readyToPlay,
              !hasEnded, !isSwitchingAudioMode, !isPreparingFastPlayback, !fastPlayback.failed,
              let video = currentVideo else { return }
        guard !video.isLive, !video.id.hasPrefix("fetch-") else {
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            return
        }
        isPreparingFastPlayback = true
        fastPlaybackPreparation = .init(phase: .resolving, completedBytes: 0, totalBytes: nil)
        fastPlayback.generation &+= 1
        let generation = fastPlayback.generation
        let session = playbackSessionID
        let quality = playbackQuality
        log.info("Fast playback experiment started for \(video.id, privacy: .public) requested=\(self.requestedTransportRate, privacy: .public)x")
        fastPlayback.task = Task { [weak self] in
            await self?.prepareFastPlayback(for: video, quality: quality, originalItem: item, session: session, generation: generation)
        }
        scheduleFastPlaybackTimeout(after: .seconds(30), generation: generation)
    }

    private func scheduleFastPlaybackTimeout(after duration: Duration, generation: Int) {
        fastPlayback.timeoutTask?.cancel()
        fastPlayback.timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.fastPlayback.generation == generation,
                  !self.fastPlayback.isInstalling else { return }
            self.log.notice("Fast playback extraction/preparation timed out")
            self.cancelFastPlaybackPreparation()
            self.failFastPlayback(message: "Higher speeds are unavailable for this video")
        }
    }

    func applyEffectivePlaybackRate() {
        effectivePlaybackRate = fastPlayback.applyRate(
            to: player,
            baseRate: playbackRate,
            isPlaying: isPlaying
        )
    }

    func cancelFastPlaybackPreparation() {
        fastPlayback.cancelPreparation()
        isPreparingFastPlayback = false
        fastPlaybackPreparation = nil
    }

    func cancelPendingFastPlayback() {
        guard isPreparingFastPlayback else { return }
        cancelFastPlaybackPreparation()
        fastPlayback.markCancelled()
        if playbackRate > 2 {
            playbackRate = 2
        }
        applyEffectivePlaybackRate()
        log.info("Fast playback preparation cancelled by user")
    }

    func resetFastPlaybackState() {
        fastPlayback.reset()
        isPreparingFastPlayback = false
        fastPlaybackPreparation = nil
        playbackRate = PlaybackSpeedPresets.bounded(preferences.defaultPlaybackRate)
        effectivePlaybackRate = PlaybackSpeedPresets.supportedRate(playbackRate, canPlayFastForward: false)
    }

    private func failFastPlayback(message: String) {
        fastPlayback.markFailed()
        fastPlaybackPreparation = nil
        if playbackRate > 2 {
            playbackRate = 2
        }
        applyEffectivePlaybackRate()
        showQueueNotice(message: message, haptic: false)
    }

    // MARK: - Source handoff

    private func prepareFastPlayback(
        for video: Video, quality: VideoQuality, originalItem: AVPlayerItem,
        session: Int, generation: Int
    ) async {
        var preparedLocalFile: URL?
        var installedReplacement: AVPlayerItem?
        var replacementAccepted = false
        var switchPosition: TimeInterval?
        defer {
            // A cancellation during the final item handoff must not strand the visible player
            // on a half-loaded temporary source. Restore the still-valid original item first.
            if let installedReplacement, !replacementAccepted,
               player.currentItem === installedReplacement,
               currentVideo?.id == video.id, playbackSessionID == session {
                let resume = fastPlayback.resumeAfterSwitch == true
                player.pause()
                fastPlayback.isInstalling = false
                loadItem(originalItem)
                let position = switchPosition ?? elapsed
                player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600))
                pendingSeekTarget = nil
                loadState = .readyToPlay
                if resume { play() }
            }
            if let preparedLocalFile, fastPlayback.localFileURL != preparedLocalFile {
                FastPlaybackLocalFileService.remove(preparedLocalFile)
            }
            if fastPlayback.generation == generation {
                fastPlayback.task = nil
                fastPlayback.timeoutTask?.cancel()
                fastPlayback.timeoutTask = nil
                isPreparingFastPlayback = false
                fastPlaybackPreparation = nil
                fastPlayback.isInstalling = false
                fastPlayback.resumeAfterSwitch = nil
            }
        }
        let replacement: AVPlayerItem
        do {
            let prepared = try await fastPlaybackCandidatePreparer.prepare(
                video: video,
                quality: quality,
                referenceDuration: originalItem.duration.seconds,
                resolver: resolver,
                itemFactory: itemFactory,
                onCompositePreparation: { [weak self] in
                    self?.scheduleFastPlaybackTimeout(after: .seconds(1_200), generation: generation)
                },
                onProgress: { [weak self] update in
                    guard let self, self.fastPlayback.generation == generation,
                          self.playbackSessionID == session else { return }
                    self.fastPlaybackPreparation = update
                }
            )
            preparedLocalFile = prepared.temporaryFile
            replacement = prepared.item
        } catch {
            guard !Task.isCancelled, fastPlayback.generation == generation,
                  playbackSessionID == session else { return }
            // Keep signed stream URLs out of diagnostics. Error type + code distinguish
            // transfer, export and probe failures without logging NSError userInfo.
            log.notice("Fast playback candidate rejected before swap: \(PlayerItemReadinessGate.describe(itemError: error), privacy: .public) type=\(String(reflecting: type(of: error)), privacy: .public)")
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            return
        }
        guard !Task.isCancelled, fastPlayback.generation == generation,
              playbackSessionID == session, currentVideo?.id == video.id,
              playbackQuality == quality, requestedTransportRate > 2,
              !hasEnded, player.currentItem === originalItem, loadState == .readyToPlay else { return }

        // Capture the position at the handoff, not when extraction started. Any playback and
        // seeks performed while the progressive URL was resolving must carry into the new item.
        let time = player.currentTime().seconds
        let position = time.isFinite && time >= 0 ? time : elapsed
        switchPosition = position
        let originalSeekableEnd = originalItem.seekableTimeRanges
            .map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }
            .filter { $0.isFinite && $0 >= 0 }
            .max()
        let previousSize = videoPresentationSize
        fastPlayback.resumeAfterSwitch = isPlaying
        fastPlayback.isInstalling = true
        fastPlayback.timeoutTask?.cancel()
        player.pause()
        pendingSeekTarget = position
        seekRequestID += 1
        loadState = .buffering
        itemLoadStartedAt = Date()
        loadItem(replacement)
        installedReplacement = replacement
        let readiness = await readinessGate.wait(for: replacement, timeout: .seconds(12))
        guard !Task.isCancelled, fastPlayback.generation == generation,
              playbackSessionID == session, player.currentItem === replacement else { return }

        if case .ready = readiness, replacement.canPlayFastForward {
            let originalDuration = originalItem.duration.seconds
            let replacementDuration = replacement.duration.seconds
            if originalDuration.isFinite, replacementDuration.isFinite,
               abs(originalDuration - replacementDuration) > 2 {
                // A shorter HLS timeline may be a truncated stream, a partial seekable window,
                // or a different timebase. Do not scale the handoff seek without independent
                // evidence: doing so could jump to the wrong scene. Keep enough URL-free facts
                // here to distinguish those cases from the next device log.
                log.notice("Fast playback timeline discrepancy: hls=\(originalDuration, privacy: .public)s seekableEnd=\(originalSeekableEnd ?? -1, privacy: .public)s metadata=\(video.duration ?? -1, privacy: .public)s prepared=\(replacementDuration, privacy: .public)s handoff=\(position, privacy: .public)s")
            }
            await seekForSourceSwitch(to: pendingSeekTarget ?? position, item: replacement)
            guard !Task.isCancelled, fastPlayback.generation == generation, playbackSessionID == session,
                  player.currentItem === replacement else { return }
            pendingSeekTarget = nil
            loadState = .readyToPlay
            applyEffectivePlaybackRate()
            if fastPlayback.resumeAfterSwitch == true { play() } else { isPlaying = false }
            fastPlayback.localFileURL = preparedLocalFile
            replacementAccepted = true
            log.info("Fast progressive playback accepted: source=\(preparedLocalFile == nil ? "direct" : "temporary-local", privacy: .public) requested=\(self.requestedTransportRate, privacy: .public)x effective=\(self.effectivePlaybackRate, privacy: .public)x actual=\(self.player.rate, privacy: .public)x canPlayFastForward=\(replacement.canPlayFastForward, privacy: .public) pitch=\(replacement.audioTimePitchAlgorithm, privacy: .public)")
        } else {
            log.notice("Fast playback swap rejected; restoring original stream")
            loadItem(originalItem)
            videoPresentationSize = previousSize
            await seekForSourceSwitch(to: pendingSeekTarget ?? position, item: originalItem)
            guard !Task.isCancelled, fastPlayback.generation == generation, playbackSessionID == session,
                  player.currentItem === originalItem else { return }
            pendingSeekTarget = nil
            loadState = .readyToPlay
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            if fastPlayback.resumeAfterSwitch == true { play() } else { isPlaying = false }
        }
        updateNowPlaying()
    }

}
