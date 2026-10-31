import Foundation
import OSLog

/// Previous/Next navigation and playlist queue commands.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Queue navigation

    func playNext() {
        log.info("playNext() — queue size=\(self.queue.items.count, privacy: .public) currentIndex=\(self.queue.currentIndex, privacy: .public)")
        if let item = playbackHistory.moveForward(where: { !VideoBlocklist.shared.blocks($0) }) {
            load(
                item.video,
                skipRecommendations: item.skipRecommendations,
                expandPlayer: false,
                recordInPlaybackHistory: false,
                preservePlaylistPosition: item.preservesPlaylistPosition
            )
            return
        }
        if let next = manualQueue.first(where: { !VideoBlocklist.shared.blocks($0) }) {
            playManualQueueItem(next, expandPlayer: false)
            return
        }
        if let next = nextUnblockedQueueVideo() {
            load(next, skipRecommendations: !queueAcceptsRecommendations, expandPlayer: false)
            return
        }
        // Queue at end. If this queue accepts recommendations and the user hasn't asked for
        // repeat-all/repeat-one, refill from the last item's recommendations and try advancing
        // again — that's the "endless queue" behavior: every time we hit the bottom, more recs
        // refill behind us.
        guard queueAcceptsRecommendations,
              queue.repeatMode == .off,
              let seed = currentVideo ?? queue.items.last else {
            log.notice("playNext: queue at end, no recs refill (acceptsRecs=\(self.queueAcceptsRecommendations, privacy: .public), repeat=\(String(describing: self.queue.repeatMode), privacy: .public))")
            return
        }
        log.info("playNext: queue at end, refilling recs from seed=\(seed.id, privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            let countBefore = self.queue.items.count
            await self.fillQueueWithRecommendations(for: seed)
            guard self.queue.items.count > countBefore else {
                self.log.notice("playNext: refill produced no new items, giving up")
                return
            }
            if let next = self.nextUnblockedQueueVideo() {
                self.load(next, skipRecommendations: !self.queueAcceptsRecommendations, expandPlayer: false)
            }
        }
    }

    /// Previously queued videos can become blocked while Settings is open. Skip them without
    /// changing the currently playing item or looping forever under repeat-all/one.
    private func nextUnblockedQueueVideo() -> Video? {
        for _ in 0..<queue.items.count {
            guard let next = queue.advance() else { return nil }
            if !VideoBlocklist.shared.blocks(next) { return next }
        }
        return nil
    }

    func playPrevious() {
        log.info("playPrevious() — history size=\(self.playbackHistory.count, privacy: .public) index=\(self.playbackHistory.currentIndex, privacy: .public)")
        guard playbackHistory.canMoveBackward else {
            log.notice("playPrevious: at start of playback history")
            return
        }
        guard let item = playbackHistory.moveBackward(where: { !VideoBlocklist.shared.blocks($0) })
        else { return }
        load(
            item.video,
            skipRecommendations: item.skipRecommendations,
            expandPlayer: false,
            recordInPlaybackHistory: false,
            preservePlaylistPosition: item.preservesPlaylistPosition
        )
    }

    /// Starts playback with an explicit playlist context. Unlike a generic recommendation queue,
    /// this retains the playlist title and continuation so the player can identify and extend it.
    // MARK: - Playlist context

    func loadPlaylist(
        _ details: PlaylistDetails,
        startAt video: Video,
        shuffled: Bool = false,
        origin: PlaylistPlaybackOrigin = .youtube
    ) {
        let allowed = details.videos.filter { !VideoBlocklist.shared.blocks($0) }
        let videos = shuffled ? allowed.shuffled() : allowed
        guard videos.contains(where: { $0.id == video.id }) else { return }
        queue.isShuffleOn = false
        queue.replace(with: videos)
        if shuffled { queue.isShuffleOn = true }
        load(video, skipRecommendations: true)
        playlistContext.begin(details.playlist, origin: origin, continuationToken: details.continuationToken)
        recommendations.clearPlaylistItems()
    }

    /// Restores History's playlist around a video that is already resolving or playing. The
    /// AVPlayerItem is untouched; only the upcoming queue and playlist panel gain context.
    func attachPlaylistFromHistory(
        _ details: PlaylistDetails,
        origin: PlaylistPlaybackOrigin,
        videoID: String,
        playbackSessionID expectedSessionID: Int
    ) {
        guard playbackSessionID == expectedSessionID,
              currentVideo?.id == videoID,
              activePlaylist == nil,
              let index = details.videos.filter({ !VideoBlocklist.shared.blocks($0) })
                .firstIndex(where: { $0.id == videoID }) else { return }
        let visibleVideos = details.videos.filter { !VideoBlocklist.shared.blocks($0) }
        recommendations.cancel()
        recommendations.resetPager()
        recommendations.clearPlaylistItems()
        queue.isShuffleOn = false
        queue.replace(with: visibleVideos, startAt: index)
        if let currentVideo { queue.updateVideo(currentVideo) }
        queueAcceptsRecommendations = false
        playlistContext.begin(details.playlist, origin: origin, continuationToken: details.continuationToken)
        playbackHistory.replaceCurrent(.init(
            video: currentVideo ?? visibleVideos[index],
            skipRecommendations: true,
            preservesPlaylistPosition: false
        ))
        if preferences.recordsWatchHistory {
            Task {
                await PersistenceWriter.shared.updateWatchHistoryPlaylistContext(
                    videoID: videoID,
                    playlistID: details.playlist.id,
                    playlistTitle: details.playlist.title,
                    playlistOrigin: origin
                )
            }
        }
    }

    /// Detaches playlist navigation without touching the installed AVPlayerItem or playhead.
    /// The current video becomes a standalone recommendation seed; previously fetched suggestions
    /// remain available while the normal refill path tops them up in the background.
    func leavePlaylist() {
        guard let currentVideo, let playlist = activePlaylist else { return }
        let departedPlaylistID = playlist.id
        log.info("Leaving playlist while continuing (currentVideo.id, privacy: .public)")
        recommendations.cancel()

        let suggestions = playlistRecommendations.filter {
            $0.id != currentVideo.id && !VideoBlocklist.shared.blocks($0)
        }
        playlistContext.clear()
        recommendations.clearPlaylistItems()
        queueAcceptsRecommendations = true
        recommendations.resetPager()
        queue.replace(with: [currentVideo] + suggestions)
        queue.isShuffleOn = false

        playbackHistory.replaceCurrent(.init(
            video: currentVideo,
            skipRecommendations: false,
            preservesPlaylistPosition: false
        ))
        if preferences.recordsWatchHistory {
            Task {
                await PersistenceWriter.shared.updateWatchHistoryPlaylistContext(
                    videoID: currentVideo.id,
                    playlistID: nil,
                    playlistTitle: nil,
                    playlistOrigin: nil,
                    onlyIfCurrentPlaylistID: departedPlaylistID
                )
            }
        }
        scheduleRecommendationFill(for: currentVideo)
    }

    var canLoadMorePlaylistItems: Bool { playlistContext.canLoadMore }

    func loadMorePlaylistItems() async { await playlistContext.loadMore() }

    var isLoadingMoreQueueItems: Bool {
        isLoadingMorePlaylistVideos || isLoadingMoreRecommendations
    }

}
