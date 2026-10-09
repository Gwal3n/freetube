import Observation

/// Opens History immediately, then restores its optional playlist without restarting playback.
@available(iOS 17.0, *)
@Observable
@MainActor
final class HistoryPlaybackViewModel {
    static let shared = HistoryPlaybackViewModel()

    @ObservationIgnored private let playlists = HistoryPlaylistRestorationService()
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private let log = AppLog(subsystem: "com.leshko.freetube", category: "HistoryPlayback")

    func open(_ entry: WatchHistorySnapshot, video: Video, player: PlayerStateManager) {
        restorationTask?.cancel()
        player.load(video)
        guard entry.playlistID != nil, let origin = entry.playlistOrigin else { return }
        let sessionID = player.playbackSessionID
        restorationTask = Task { [weak self, weak player] in
            guard let self else { return }
            do {
                guard let details = try await playlists.restore(for: entry),
                      !Task.isCancelled else { return }
                player?.attachPlaylistFromHistory(
                    details,
                    origin: origin,
                    videoID: entry.videoID,
                    playbackSessionID: sessionID
                )
            } catch is CancellationError {
                return
            } catch {
                log.notice("History playlist could not be restored for \(entry.videoID, privacy: .public)")
            }
        }
    }
}
