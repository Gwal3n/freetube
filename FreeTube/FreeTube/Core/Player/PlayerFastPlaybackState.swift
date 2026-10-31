import AVFoundation
import Foundation

/// Internal lifetime state for a high-speed source attempt. Visible rate and preparation
/// progress remain on PlayerStateManager so its SwiftUI observation surface stays unchanged.
@available(iOS 17.0, *)
@MainActor
struct PlayerFastPlaybackState {
    var task: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    var generation = 0
    var failed = false
    var userRequested = false
    var localFileURL: URL?
    var isInstalling = false
    var resumeAfterSwitch: Bool?
    var temporaryRate: Double?
    var wasPlayingBeforeTemporaryRate: Bool?

    mutating func select(_ rate: Double, isPreparing: Bool) -> Double {
        let bounded = PlaybackSpeedPresets.bounded(rate)
        if bounded > 2 {
            userRequested = true
            if !isPreparing { failed = false }
        }
        return bounded
    }

    mutating func beginTemporary(_ rate: Double, wasPlaying: Bool) -> Bool {
        guard temporaryRate == nil else { return false }
        wasPlayingBeforeTemporaryRate = wasPlaying
        temporaryRate = PlaybackSpeedPresets.bounded(rate)
        return true
    }

    /// Returns whether playback was paused before the hold, or nil if there was no hold.
    mutating func endTemporary() -> Bool? {
        guard temporaryRate != nil else { return nil }
        let restorePaused = wasPlayingBeforeTemporaryRate == false
        temporaryRate = nil
        wasPlayingBeforeTemporaryRate = nil
        return restorePaused
    }

    mutating func markCancelled() {
        failed = true
        userRequested = false
        temporaryRate = nil
        wasPlayingBeforeTemporaryRate = nil
    }

    mutating func markFailed() {
        failed = true
        userRequested = false
    }

    func requestedRate(baseRate: Double) -> Double { temporaryRate ?? baseRate }

    /// Keep unsupported HLS transport rates capped while allowing a prepared local item to
    /// use its validated fast-forward capability and voice-oriented pitch correction.
    func applyRate(to player: AVQueuePlayer, baseRate: Double, isPlaying: Bool) -> Double {
        let item = player.currentItem
        let supportsFastPlayback = item?.status == .readyToPlay && item?.canPlayFastForward == true
        let requested = requestedRate(baseRate: baseRate)
        let effective = PlaybackSpeedPresets.supportedRate(
            requested, canPlayFastForward: supportsFastPlayback
        )
        let defaultRate = Float(PlaybackSpeedPresets.supportedRate(
            baseRate, canPlayFastForward: supportsFastPlayback
        ))
        if player.defaultRate != defaultRate { player.defaultRate = defaultRate }
        if supportsFastPlayback, requested > 2, item?.audioTimePitchAlgorithm != .timeDomain {
            item?.audioTimePitchAlgorithm = .timeDomain
        }
        if isPlaying, !isInstalling, player.rate != Float(effective) {
            player.rate = Float(effective)
        }
        return effective
    }

    mutating func cancelPreparation() {
        generation &+= 1
        task?.cancel()
        task = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    mutating func reset() {
        cancelPreparation()
        isInstalling = false
        resumeAfterSwitch = nil
        failed = false
        userRequested = false
        temporaryRate = nil
        wasPlayingBeforeTemporaryRate = nil
    }
}
