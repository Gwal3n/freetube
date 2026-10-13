import Foundation

/// Owns the session's watch-history qualification and progress-write bookkeeping.
/// The player supplies observed playback time, not the playhead, so seeking cannot
/// qualify an otherwise unwatched video.
@MainActor
final class PlayerWatchHistoryTracker {
    private var playbackSeconds: TimeInterval = 0
    private var lastPlaybackTick: Date?
    private var recordedVideoID: String?
    private var lastProgressSaveAt = Date.distantPast
    private var lastSavedProgressVideoID: String?
    private var lastSavedProgressPosition: TimeInterval = -.infinity

    func reset() {
        playbackSeconds = 0
        lastPlaybackTick = nil
        recordedVideoID = nil
        lastProgressSaveAt = .distantPast
        lastSavedProgressVideoID = nil
        lastSavedProgressPosition = -.infinity
    }

    func hasRecorded(_ videoID: String) -> Bool {
        recordedVideoID == videoID
    }

    func hasQualifiedForHistory(duration: TimeInterval) -> Bool {
        playbackSeconds >= min(duration * 0.05, 10)
    }

    func recordOnOpen(
        _ video: Video,
        recordsHistory: Bool,
        addWhenOpened: Bool,
        playlist: Playlist?,
        playlistOrigin: PlaylistPlaybackOrigin?
    ) {
        guard recordsHistory, addWhenOpened, !video.id.hasPrefix("fetch-") else { return }
        recordedVideoID = video.id
        Task {
            await PersistenceWriter.shared.upsertWatchHistory(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                channelID: video.channelID,
                thumbnailURL: video.thumbnailURL,
                position: 0,
                duration: video.duration ?? 0,
                saveProgress: false,
                playlistID: playlist?.id,
                playlistTitle: playlist?.title,
                playlistOrigin: playlist == nil ? nil : playlistOrigin
            )
        }
    }

    func updateMetadataIfRecorded(_ video: Video, recordsHistory: Bool) {
        guard recordsHistory, hasRecorded(video.id) else { return }
        Task {
            await PersistenceWriter.shared.updateWatchHistoryMetadata(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                channelID: video.channelID,
                thumbnailURL: video.thumbnailURL
            )
        }
    }

    /// A short opening or nearly finished playback must not become a resume point.
    func resumePosition(
        _ progress: (position: TimeInterval, duration: TimeInterval)?,
        for videoID: String,
        currentVideoID: String?,
        duration: TimeInterval,
        recordsProgress: Bool
    ) -> TimeInterval? {
        guard recordsProgress,
              currentVideoID == videoID,
              let progress,
              progress.position.isFinite,
              progress.position >= 10 else { return nil }
        let knownDuration = duration > 0 ? duration : progress.duration
        guard knownDuration > 0,
              knownDuration - progress.position >= 30,
              progress.position < knownDuration * 0.95 else { return nil }
        return progress.position
    }

    func persist(
        video: Video?,
        elapsed: TimeInterval,
        duration: TimeInterval,
        force: Bool,
        recordsHistory: Bool,
        recordsProgress: Bool,
        playlist: Playlist?,
        playlistOrigin: PlaylistPlaybackOrigin?
    ) {
        guard recordsHistory else {
            recordedVideoID = nil
            playbackSeconds = 0
            lastPlaybackTick = nil
            return
        }
        guard let video,
              !video.id.hasPrefix("fetch-"),
              elapsed.isFinite,
              duration.isFinite,
              elapsed >= 0,
              duration > 0 else { return }
        guard hasQualifiedForHistory(duration: duration) else { return }

        if recordedVideoID != video.id {
            recordedVideoID = video.id
            lastProgressSaveAt = Date()
            lastSavedProgressVideoID = video.id
            lastSavedProgressPosition = elapsed
            Task {
                await PersistenceWriter.shared.upsertWatchHistory(
                    videoID: video.id,
                    title: video.title,
                    channelName: video.channelName,
                    channelID: video.channelID,
                    thumbnailURL: video.thumbnailURL,
                    position: elapsed,
                    duration: duration,
                    saveProgress: recordsProgress,
                    playlistID: playlist?.id,
                    playlistTitle: playlist?.title,
                    playlistOrigin: playlist == nil ? nil : playlistOrigin
                )
            }
            return
        }
        guard recordsProgress else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastProgressSaveAt) < 10 { return }
        if lastSavedProgressVideoID == video.id,
           abs(lastSavedProgressPosition - elapsed) < 0.5 { return }

        lastProgressSaveAt = now
        lastSavedProgressVideoID = video.id
        lastSavedProgressPosition = elapsed
        Task {
            await PersistenceWriter.shared.updateWatchProgress(
                videoID: video.id,
                position: elapsed,
                duration: duration,
                notifyObservers: force
            )
        }
    }

    func accumulatePlaybackTime(isPlaying: Bool, recordsHistory: Bool, now: Date = Date()) {
        guard recordsHistory else {
            recordedVideoID = nil
            playbackSeconds = 0
            lastPlaybackTick = nil
            return
        }
        guard isPlaying else {
            lastPlaybackTick = nil
            return
        }
        if let previous = lastPlaybackTick {
            // A delayed observer callback cannot count unobserved background time.
            playbackSeconds += min(max(now.timeIntervalSince(previous), 0), 1)
        }
        lastPlaybackTick = now
    }
}
