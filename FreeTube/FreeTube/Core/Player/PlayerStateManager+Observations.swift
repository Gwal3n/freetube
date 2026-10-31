import AVFoundation
import Foundation
import OSLog

/// AVPlayer time, transport, and item-end observations for the shared player.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Player observations

    /// Read the window AVPlayer actually offers, rather than inferring DVR support from the
    /// manifest URL. Live ranges can appear after readiness and move as the broadcast advances.
    private func updateLiveSeekableRange(for item: AVPlayerItem) {
        guard currentVideo?.isLive == true,
              loadState == .readyToPlay,
              item.status == .readyToPlay else { return }
        // A seek bar cannot safely cross a gap. Use the most recent contiguous range if the
        // manifest ever reports several, and let AVPlayer keep advancing its moving bounds.
        let newest = item.seekableTimeRanges.compactMap { value -> ClosedRange<TimeInterval>? in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
            return start...end
        }.max { $0.upperBound < $1.upperBound }
        if liveSeekableRange != newest { liveSeekableRange = newest }
    }

    func installObservers() {
        // AVPlayer pauses for calls/Siri on its own. Preserve the user's play intent separately
        // from `isPlaying`, which KVO may already have changed by the time this arrives.
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard let rawType,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.interruptedPlaybackSessionID = self.wantsPlayback && self.player.currentItem != nil
                        ? self.playbackSessionID : nil
                case .ended:
                    let interruptedSessionID = self.interruptedPlaybackSessionID
                    self.interruptedPlaybackSessionID = nil
                    guard self.preferences.resumeAfterAudioInterruption,
                          AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume),
                          interruptedSessionID == self.playbackSessionID,
                          self.wantsPlayback,
                          self.player.currentItem != nil,
                          self.player.timeControlStatus == .paused else { return }
                    self.play()
                @unknown default:
                    break
                }
            }
        }
        observations.installPlayerObservers(
            on: player,
            onTime: { [weak self] in self?.handleTimeTick($0) },
            onEnd: { [weak self] in self?.handleItemEnd($0) },
            onTransportChange: { [weak self] in self?.handleTransportChange() }
        )
    }

    private func handleTimeTick(_ time: CMTime) {
        elapsed = pendingSeekTarget ?? (time.seconds.isFinite ? time.seconds : 0)
        if let item = player.currentItem {
            if isPlaying,
               let fps = item.tracks.map(\.currentVideoFrameRate).first(where: {
                   $0.isFinite && $0 >= 10 && $0 <= 240
               }) {
                observedFrameRate = (item, Double(fps))
            }
            let total = item.duration.seconds
            if total.isFinite { duration = total }
            updateLiveSeekableRange(for: item)
            if currentVideo?.isLive == true,
               loadState == .readyToPlay,
               item.status == .readyToPlay {
                itemDiagnostics.logLiveDVRIfNeeded(
                    for: item,
                    videoID: currentVideo?.id ?? "unknown"
                )
            }
        }
        accumulateHistoryPlaybackTime()
        persistCurrentPlaybackProgress(force: false)
        updateNowPlaying()
    }

    /// The queue retains an ended item so replay and backward seeking can reuse it.
    private func handleItemEnd(_ endedItem: AVPlayerItem) {
        guard endedItem === player.currentItem else { return }
        log.info("Playback reached item end: sourceDuration=\(endedItem.duration.seconds, privacy: .public)s metadataDuration=\(currentVideo?.duration ?? -1, privacy: .public)s")
        isPlaying = false
        wantsPlayback = false
        hasEnded = true
        elapsed = duration
        persistCurrentPlaybackProgress(force: true)
        updateNowPlaying()
        if sleepTimerOption == .endOfVideo {
            setSleepTimer(.off)
            return
        }
        if queue.repeatMode == .one || preferences.autoplayNext {
            playNext()
        }
    }

    /// Read the current transport status after the KVO hop; a captured status may be stale.
    private func handleTransportChange() {
        switch player.timeControlStatus {
        case .playing:
            if !isPlaying {
                log.info("KVO timeControlStatus → playing (sync isPlaying=true)")
                isPlaying = true
            }
        case .paused:
            if isPlaying {
                log.info("KVO timeControlStatus → paused (sync isPlaying=false)")
                isPlaying = false
            }
        case .waitingToPlayAtSpecifiedRate:
            if !isPlaying { isPlaying = true }
        @unknown default:
            break
        }
    }

    // MARK: - Now Playing

    func updateNowPlaying() {
        guard let video = currentVideo else { return }
        NowPlayingCenter.update(
            title: video.title,
            artist: video.channelName,
            duration: duration,
            elapsed: elapsed,
            rate: isPlaying ? Float(effectivePlaybackRate) : 0.0,
            artwork: currentArtwork
        )
    }

}
