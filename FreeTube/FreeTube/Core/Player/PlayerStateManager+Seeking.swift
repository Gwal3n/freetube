import AVFoundation
import Foundation
import OSLog

/// Playhead seeking, frame stepping, and live-edge navigation.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Playhead seeking

    func seek(
        to seconds: TimeInterval,
        rearmSponsorBlock: Bool = true,
        resumeAfterEnded: Bool = true,
        evaluateSponsorBlockAfterSeek: Bool = true
    ) {
        log.info("seek(to: \(seconds, privacy: .public)s)")
        guard seconds.isFinite else { return }
        let boundedSeconds: TimeInterval
        if currentVideo?.isLive == true {
            guard let range = liveSeekableRange else { return }
            boundedSeconds = min(max(seconds, range.lowerBound), range.upperBound)
        } else {
            boundedSeconds = max(0, duration > 0 ? min(seconds, duration) : seconds)
        }
        let shouldResume = resumeAfterEnded && hasEnded && boundedSeconds < max(0, duration - 0.25)
        if shouldResume {
            hasEnded = false
        }
        // Any segment whose end is still ahead of the new position becomes eligible again. This
        // makes rewinding before a previously skipped segment behave like a fresh encounter.
        if rearmSponsorBlock {
            sponsorBlockCoordinator.rearm(afterSeekingTo: boundedSeconds, segments: sponsorBlockSegments)
        }
        // Update optimistically so rapid continuation taps accumulate from the last requested
        // target instead of the periodic observer's up-to-0.5-second-old playback position.
        elapsed = boundedSeconds
        pendingSeekTarget = boundedSeconds
        seekRequestID += 1
        let requestID = seekRequestID
        let time = CMTime(seconds: boundedSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                // Let any periodic callback queued just before seek completion drain while the
                // optimistic target is still pinned. Otherwise that stale tick briefly paints the
                // scrubber at its pre-seek position before the next AVPlayer tick corrects it.
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.seekRequestID == requestID else { return }
                self.pendingSeekTarget = nil
                let settledTime = self.player.currentTime().seconds
                if settledTime.isFinite {
                    self.elapsed = settledTime
                    if evaluateSponsorBlockAfterSeek {
                        self.handleSponsorBlockSegment(at: settledTime)
                    } else {
                        self.log.info("Fine seek settled target=\(boundedSeconds, privacy: .public)s actual=\(settledTime, privacy: .public)s")
                    }
                    if self.currentVideo?.isLive == true {
                        self.log.info("Live DVR seek settled target=\(boundedSeconds, privacy: .public)s actual=\(settledTime, privacy: .public)s")
                    }
                }
                if shouldResume {
                    self.play()
                }
            }
        }
    }

    func seekRelative(by delta: TimeInterval) {
        log.info("seekRelative(by: \(delta, privacy: .public)s)")
        if currentVideo?.isLive == true {
            guard let range = liveSeekableRange else { return }
            seek(to: min(max(elapsed, range.lowerBound), range.upperBound) + delta)
        } else {
            seek(to: max(0, min(elapsed + delta, duration)))
        }
    }

    /// Use AVFoundation's decoded-frame step when supported. HLS commonly lacks that capability;
    /// for those items, seek by the observed frame interval (or approximately 1/30 second).
    // MARK: - Fine and live seeking

    func stepFrame(by count: Int) {
        log.info("Fine step requested direction=\(count, privacy: .public)")
        guard count == -1 || count == 1,
              !isPlaying,
              player.timeControlStatus == .paused,
              (count < 0 ? canStepFrameBackward : canStepFrameForward),
              let item = player.currentItem else { return }
        if hasEnded && count < 0 { hasEnded = false }
        if pendingSeekTarget == nil,
           (count < 0 ? item.canStepBackward : item.canStepForward) {
            log.info("Native frame step direction=\(count, privacy: .public)")
            item.step(byCount: count)
            let steppedTime = item.currentTime().seconds
            if steppedTime.isFinite {
                elapsed = steppedTime
                updateNowPlaying()
            }
        } else {
            let frameRate: Double
            if let observedFrameRate, observedFrameRate.item === item {
                frameRate = observedFrameRate.fps
            } else {
                frameRate = 30
            }
            let playerTime = item.currentTime().seconds
            let position = pendingSeekTarget
                ?? (playerTime.isFinite ? playerTime : elapsed)
            let target = position + Double(count) / frameRate
            log.info("Timed fine step direction=\(count, privacy: .public) fps=\(frameRate, privacy: .public) target=\(target, privacy: .public)s")
            seek(
                to: target,
                rearmSponsorBlock: false,
                resumeAfterEnded: false,
                evaluateSponsorBlockAfterSeek: false
            )
        }
    }

    /// Ask AVPlayer to return to its live edge. A rolling HLS window can move between drawing
    /// the timeline and tapping LIVE, so a finite seek to a cached end time is less reliable.
    func seekToLive() {
        guard currentVideo?.isLive == true, let range = liveSeekableRange else { return }
        log.info("seekToLive()")
        seekRequestID += 1
        let requestID = seekRequestID
        pendingSeekTarget = range.upperBound
        elapsed = range.upperBound
        player.seek(to: .positiveInfinity) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekRequestID == requestID else { return }
                self.pendingSeekTarget = nil
                if finished {
                    let settledTime = self.player.currentTime().seconds
                    if settledTime.isFinite { self.elapsed = settledTime }
                    self.log.info("Live DVR returned to live edge at \(settledTime, privacy: .public)s")
                } else {
                    self.log.notice("Live DVR return-to-live seek did not complete")
                }
            }
        }
    }

}
