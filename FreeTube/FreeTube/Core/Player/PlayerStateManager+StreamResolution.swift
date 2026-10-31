import AVFoundation
import Foundation
import OSLog

/// Stream candidate resolution, AVPlayerItem installation, readiness, and recovery.
@available(iOS 17.0, *)
extension PlayerStateManager {
    // MARK: - Item installation and observation

    /// Swap the player to a new item using the `AVQueuePlayer`-correct pattern. `replaceCurrentItem`
    /// is documented to be a no-op when the player's internal queue is empty (which is our usual
    /// state since the playable URL is short-lived and we never preload), so we always tear the
    /// queue down to nothing first and then insert. Also wires KVO so we hear about decode/auth
    /// failures the moment they happen (CoreMedia's `CFByteFlume err=-12939` style messages don't
    /// surface a structured `NSError` otherwise).
    func loadItem(_ item: AVPlayerItem, originalAudioLanguageCode: String? = nil) {
        // Do not log the asset URL or path. Direct YouTube assets contain signed credentials in
        // both components; the candidate strategy is logged immediately before this method.
        let assetKind = item.asset is AVURLAsset ? "URL" : "composition"
        log.info("loadItem: removeAllItems + insert (assetKind=\(assetKind, privacy: .public))")
        player.removeAllItems()
        if let localFileURL = fastPlayback.localFileURL,
           (item.asset as? AVURLAsset)?.url != localFileURL {
            fastPlayback.localFileURL = nil
            FastPlaybackLocalFileService.remove(localFileURL)
        }
        player.insert(item, after: nil)
        applyEffectivePlaybackRate()
        PlayerMediaSelection.configure(
            item: item,
            on: player,
            originalAudioLanguageCode: originalAudioLanguageCode,
            log: log
        )
        log.debug("loadItem: queue size after insert=\(self.player.items().count, privacy: .public)")
        observe(item: item)
    }

    private func observe(item: AVPlayerItem) {
        observations.clearItem()
        bufferedRanges = []
        liveSeekableRange = nil
        observedFrameRate = nil
        itemDiagnostics.reset()

        observations.itemStatus = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                switch item.status {
                case .unknown:
                    self.log.info("AVPlayerItem status: unknown")
                case .readyToPlay:
                    let preparationTime = self.itemLoadStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    self.log.info("AVPlayerItem status: readyToPlay after \(preparationTime, privacy: .public)s (duration=\(item.duration.seconds, privacy: .public)s)")
                    self.log.info("AVPlayerItem fast playback: canPlayFastForward=\(item.canPlayFastForward, privacy: .public) defaultRate=\(self.player.defaultRate, privacy: .public) audioPitchAlgorithm=\(item.audioTimePitchAlgorithm, privacy: .public)")
                    self.log.info("AVPlayerItem frame stepping: backward=\(item.canStepBackward, privacy: .public) forward=\(item.canStepForward, privacy: .public) tracks=\(item.tracks.count, privacy: .public)")
                    self.itemDiagnostics.logAudio(
                        for: item,
                        allowsMixing: self.preferences.allowAudioMixing
                    )
                    self.itemLoadStartedAt = nil
                    self.readinessGate.finish(.ready, for: item)
                    // Local-file playback has no resolveAndPlay readiness branch. Normal stream
                    // and audio-mode switches reconcile after their own acceptance/seek instead.
                    if self.player.currentItem === item, self.loadState == .readyToPlay,
                       !self.fastPlayback.isInstalling {
                        self.reconcilePlaybackRate()
                    }
                case .failed:
                    let err = item.error as NSError?
                    self.log.error("AVPlayerItem status: FAILED domain=\(err?.domain ?? "?", privacy: .public) code=\(err?.code ?? 0, privacy: .public)")
                    self.readinessGate.finish(.failed(PlayerItemReadinessGate.describe(itemError: item.error)), for: item)
                    self.recoverAcceptedStreamIfNeeded(item, reason: "item-failed")
                @unknown default:
                    break
                }
            }
        }

        observations.itemPresentationSize = item.observe(\.presentationSize, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                let size = item.presentationSize
                guard self.player.currentItem === item,
                      size.width.isFinite, size.height.isFinite,
                      size.width > 0, size.height > 0 else { return }
                self.videoPresentationSize = size
            }
        }

        observations.itemLoadedTimeRanges = item.observe(\.loadedTimeRanges, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player.currentItem === item else { return }
                let ranges: [ClosedRange<TimeInterval>] = item.loadedTimeRanges.compactMap { value in
                    let timeRange = value.timeRangeValue
                    let start = timeRange.start.seconds
                    let end = timeRange.end.seconds
                    guard start.isFinite, end.isFinite, end > max(0, start) else { return nil }
                    return max(0, start)...end
                }
                if self.bufferedRanges != ranges { self.bufferedRanges = ranges }
            }
        }

        observations.itemErrorLog = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let entry = item?.errorLog()?.events.last else { return }
            // Never include `entry.uri`: YouTube playback URLs are signed, sensitive, and
            // short-lived. Resolver identity is enough to correlate this with candidate logs.
            self?.log.error("AVPlayerItem error-log: domain=\(entry.errorDomain, privacy: .public) code=\(entry.errorStatusCode, privacy: .public) comment=\(entry.errorComment ?? "", privacy: .public)")
        }

        observations.itemFailedToEnd = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item else { return }
                self.recoverAcceptedStreamIfNeeded(item, reason: "failed-to-play-to-end")
            }
        }

        observations.itemAccessLog = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item else { return }
                self.itemDiagnostics.logAccessIfNeeded(for: item)
            }
        }
    }

    /// Only a terminal failure of the accepted, visible stream starts recovery. A stall alone
    /// remains AVPlayer's job; pre-acceptance failures stay in the startup candidate loop.
    private func recoverAcceptedStreamIfNeeded(_ item: AVPlayerItem, reason: String) {
        guard player.currentItem === item, acceptedStreamItem === item,
              let strategy = acceptedStreamStrategy, let video = currentVideo,
              loadState == .readyToPlay, !hasEnded, !isSwitchingAudioMode,
              !fastPlayback.isInstalling else { return }
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        player.pause()
        isPlaying = false
        if didAttemptPlaybackRecovery {
            log.error("Playback recovery exhausted video=\(video.id, privacy: .public) reason=\(reason, privacy: .public)")
            loadState = .failed("The video stream stopped. Please try again.")
            updateNowPlaying()
            return
        }

        didAttemptPlaybackRecovery = true
        cancelFastPlaybackPreparation()
        let recovery = playbackRecovery(for: video, excluding: strategy)
        log.notice("Playback stream failed after start video=\(video.id, privacy: .public) strategy=\(strategy.rawValue, privacy: .public) reason=\(reason, privacy: .public); trying another source")
        resolutionTask?.cancel()
        player.removeAllItems()
        loadState = .resolving
        updateNowPlaying()
        resolutionTask = Task { [weak self] in
            await self?.resolveAndPlay(video: video, autoplay: false, recovery: recovery)
        }
    }

    func playbackRecovery(
        for video: Video,
        excluding failedStrategy: PlaybackStrategy?,
        resumeFromHistoryIfUnstarted: Bool = false
    ) -> PlayerPlaybackRecovery {
        PlayerPlaybackRecovery(
            sessionID: playbackSessionID,
            failedStrategy: failedStrategy,
            currentTime: player.currentTime().seconds,
            elapsed: elapsed,
            liveSeekableRange: liveSeekableRange,
            isLive: video.isLive,
            resumeFromHistoryIfUnstarted: resumeFromHistoryIfUnstarted
        )
    }

    private func restoreRecoveredPosition(_ recovery: PlayerPlaybackRecovery, in item: AVPlayerItem) async {
        if !recovery.isLive {
            await seekForSourceSwitch(to: recovery.position, item: item)
            return
        }
        let ranges = item.seekableTimeRanges.compactMap { value -> ClosedRange<TimeInterval>? in
            let timeRange = value.timeRangeValue
            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return start...end
        }
        let target = recovery.liveSeekTarget(in: ranges).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        } ?? .positiveInfinity
        await withCheckedContinuation { continuation in
            player.seek(to: target) { _ in continuation.resume() }
        }
        guard player.currentItem === item else { return }
        let settled = player.currentTime().seconds
        if settled.isFinite { elapsed = settled }
    }

    // MARK: - Candidate resolution

    func resolveAndPlay(
        video: Video,
        autoplay: Bool,
        skipRecommendations: Bool = false,
        localFileURL: URL? = nil,
        recovery: PlayerPlaybackRecovery? = nil
    ) async {
        let sessionID = recovery?.sessionID ?? playbackSessionID
        log.info("resolveAndPlay: start for \(video.id, privacy: .public) recovery=\(recovery != nil, privacy: .public)")
        let resolutionStartedAt = Date()
        // The model-actor read runs alongside network resolution and is consumed only after the
        // winning AVPlayerItem is ready, so resume support adds no work to the critical path.
        let shouldLoadSavedProgress = recovery == nil || recovery?.resumeFromHistoryIfUnstarted == true
        let resumeLookup: Task<(position: TimeInterval, duration: TimeInterval)?, Never>? =
            shouldLoadSavedProgress ? Task {
                guard preferences.recordsWatchProgress else { return nil }
                return await PersistenceWriter.shared.watchProgress(videoID: video.id)
            } : nil
        loadState = .resolving
        var excludedStrategies = Set<PlaybackStrategy>()
        if let failedStrategy = recovery?.failedStrategy { excludedStrategies.insert(failedStrategy) }

        while !Task.isCancelled, playbackSessionID == sessionID, currentVideo?.id == video.id {
            let candidate: PlaybackCandidate
            let candidateQuality = playbackQuality
            do {
                if let localFileURL {
                    guard !excludedStrategies.contains(.localFile) else {
                        loadState = .failed("The saved video couldn’t be played from this device.")
                        return
                    }
                    candidate = PlaybackCandidate(source: .localFile(localFileURL), strategy: .localFile)
                } else {
                    candidate = try await resolver.resolve(
                        video: video,
                        quality: candidateQuality,
                        excluding: excludedStrategies
                    )
                }
            } catch is CancellationError {
                log.debug("resolveAndPlay: cancelled for \(video.id, privacy: .public)")
                return
            } catch {
                guard playbackSessionID == sessionID, currentVideo?.id == video.id else { return }
                log.error("resolveAndPlay: all resolvers failed for \(video.id, privacy: .public): \(String(describing: error), privacy: .public)")
                loadState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }

            guard !Task.isCancelled, playbackSessionID == sessionID, currentVideo?.id == video.id else {
                log.debug("resolveAndPlay: discarded stale result for \(video.id, privacy: .public)")
                return
            }

            log.info("resolveAndPlay: testing candidate=\(candidate.strategy.rawValue, privacy: .public) after \(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
            let item: AVPlayerItem
            let preparationStartedAt = Date()
            if candidate.strategy == .nativePaired {
                log.info("resolveAndPlay: preparing paired candidate for \(video.id, privacy: .public) (limit=30s)")
            }
            let outcome = await preparationGate.prepare(
                candidate: candidate,
                factory: itemFactory,
                videoID: video.id,
                timeout: .seconds(30)
            )
            guard !Task.isCancelled, playbackSessionID == sessionID,
                  currentVideo?.id == video.id else { return }
            switch outcome {
            case .ready(let preparedItem):
                item = preparedItem
                if candidate.strategy == .nativePaired {
                    log.info("resolveAndPlay: paired candidate prepared for \(video.id, privacy: .public) in \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s")
                }
            case .failed(let detail):
                if candidate.strategy == .nativePaired {
                    log.notice("resolveAndPlay: paired candidate preparation failed for \(video.id, privacy: .public) after \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s \(detail, privacy: .public)")
                } else {
                    log.notice("resolveAndPlay: candidate preparation failed strategy=\(candidate.strategy.rawValue, privacy: .public) error=\(detail, privacy: .public)")
                }
                excludedStrategies.insert(candidate.strategy)
                continue
            case .timedOut:
                log.notice("resolveAndPlay: paired candidate preparation timed out for \(video.id, privacy: .public) after \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s")
                excludedStrategies.insert(candidate.strategy)
                continue
            case .cancelled:
                return
            }
            guard !Task.isCancelled, playbackSessionID == sessionID, currentVideo?.id == video.id else { return }
            applyQualityCap(to: item)
            itemLoadStartedAt = Date()
            loadItem(item, originalAudioLanguageCode: candidate.originalAudioLanguageCode)
            // Optimistic start. AVPlayer has no "first frame rendered" signal — only
            // `.readyToPlay`, which on a warm resolve accounted for ~80% of the tap-to-video
            // wait. So we stop gating the transport on it: the candidate is still validated
            // below and still rejected on failure/timeout, but the player is already holding a
            // play request when readiness lands, so it starts without waiting for us to notice.
            // This only works because `automaticallyWaitsToMinimizeStalling` is `true` — see the
            // note in `init`, where turning it off silently discards this call.
            // Recovery waits to seek before playing, so it stays `.resolving` until ready;
            // only a normal optimistic start uses `.buffering` here.
            loadState = recovery == nil ? .buffering : .resolving
            updateNowPlaying()
            if recovery == nil, autoplay, wantsPlayback {
                log.info("resolveAndPlay: optimistic play issued for candidate=\(candidate.strategy.rawValue, privacy: .public) at \(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
                play()
            }

            let readiness = await readinessGate.wait(
                for: item,
                timeout: readinessTimeout(for: candidate.strategy)
            )
            guard !Task.isCancelled, playbackSessionID == sessionID, currentVideo?.id == video.id else {
                log.debug("resolveAndPlay: discarded candidate result for stale video \(video.id, privacy: .public)")
                return
            }

            switch readiness {
            case .ready:
                // A ready KVO event and a terminal failure can arrive before this task resumes.
                // Never bless an item that has already failed or been replaced.
                guard player.currentItem === item, item.status == .readyToPlay else {
                    log.notice("resolveAndPlay: candidate changed before acceptance strategy=\(candidate.strategy.rawValue, privacy: .public)")
                    break
                }
                if let recovery {
                    if recovery.resumeFromHistoryIfUnstarted {
                        let savedProgress = await resumeLookup?.value
                        guard !Task.isCancelled, playbackSessionID == sessionID,
                              currentVideo?.id == video.id, player.currentItem === item else { return }
                        if let position = storedResumePosition(savedProgress, for: video) {
                            log.info("Resuming \(video.id, privacy: .public) at \(position, privacy: .public)s")
                            await seekForSourceSwitch(to: position, item: item)
                        }
                    } else {
                        await restoreRecoveredPosition(recovery, in: item)
                    }
                    guard !Task.isCancelled, playbackSessionID == sessionID,
                          currentVideo?.id == video.id, player.currentItem === item else { return }
                    guard item.status == .readyToPlay else { break }
                    if !candidate.captionTracks.isEmpty { captionTracks = candidate.captionTracks }
                    if let replacementStoryboard = candidate.storyboard { storyboard = replacementStoryboard }
                    if let title = candidate.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty, let current = currentVideo, current.title != title {
                        enrichCurrentVideo(with: current.replacingTitle(with: title))
                    }
                    acceptedStreamItem = item
                    acceptedStreamStrategy = candidate.strategy
                    loadState = .readyToPlay
                    if wantsPlayback { play() } else { updateNowPlaying() }
                    reconcilePlaybackRate()
                    log.info("resolveAndPlay: recovered with candidate=\(candidate.strategy.rawValue, privacy: .public)")
                    return
                }
                // `total` still measures resolve → `.readyToPlay`, unchanged, so the number stays
                // comparable with builds that played only after this point.
                log.info("resolveAndPlay: accepted candidate=\(candidate.strategy.rawValue, privacy: .public) total=\(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
                captionTracks = candidate.captionTracks
                acceptedStreamItem = item
                acceptedStreamStrategy = candidate.strategy
                loadState = .readyToPlay
                if let title = candidate.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty, let current = currentVideo, current.title != title {
                    // The winning resolver already fetched this title alongside the stream.
                    // Updating presentation/history here costs no additional network request.
                    enrichCurrentVideo(with: current.replacingTitle(with: title))
                }
                if let nativeStoryboard = candidate.storyboard {
                    storyboard = nativeStoryboard
                }
                let savedProgress = await resumeLookup?.value
                guard !Task.isCancelled, playbackSessionID == sessionID,
                      currentVideo?.id == video.id, player.currentItem === item else { return }
                guard item.status == .readyToPlay else { return }
                applyStoredResumePosition(savedProgress, for: video)
                updateNowPlaying()
                contentPrefetchTask?.cancel()
                contentPrefetchTask = Task {
                    if preferences.prefetchVideoDetails && preferences.cacheRecentVideoContent {
                        if let info = try? await VideoContentPrefetchStore.shared.fetchDetails(videoID: video.id) {
                            self.installVideoDetails(info, for: video.id)
                        }
                        guard !Task.isCancelled else { return }
                        if preferences.showComments {
                            await VideoContentPrefetchStore.shared.prefetch(videoID: video.id)
                        }
                    }
                }
                // Usually redundant — the optimistic `play()` above has either started the item or
                // parked the player in `.waitingToPlayAtSpecifiedRate`, and this covers the case
                // where a rejected candidate left the transport paused.
                //
                // Ask the player, not `isPlaying`. That flag is a prediction written by `play()`
                // for immediate UI feedback, so after an optimistic start it reads `true` whether
                // or not AVPlayer honoured the request. Gating this on it means the one situation
                // that needs a retry is the one situation where the retry is skipped.
                if wantsPlayback, player.timeControlStatus == .paused { play() }
                finishPlaybackSetup(video: video, skipRecommendations: skipRecommendations)
                reconcilePlaybackRate()
                return
            case .failed(let description):
                log.notice("resolveAndPlay: rejected candidate=\(candidate.strategy.rawValue, privacy: .public) reason=failed detail=\(description, privacy: .public)")
            case .timedOut:
                log.notice("resolveAndPlay: rejected candidate=\(candidate.strategy.rawValue, privacy: .public) reason=readiness-timeout")
            }

            await resolver.invalidateRejectedCandidate(
                candidate,
                videoID: video.id,
                quality: candidateQuality
            )
            guard !Task.isCancelled, playbackSessionID == sessionID,
                  currentVideo?.id == video.id else { return }
            excludedStrategies.insert(candidate.strategy)
            // The optimistic `play()` left the transport running (rate 1, possibly stalled) on a
            // stream we're now abandoning. Stop it *before* tearing the queue down so `isPlaying`
            // and the Now Playing rate don't advertise playback for a rejected candidate while the
            // next one resolves.
            player.pause()
            isPlaying = false
            player.removeAllItems()
            itemLoadStartedAt = nil
            loadState = .resolving
            updateNowPlaying()
        }

        log.debug("resolveAndPlay: ended after cancellation or video change for \(video.id, privacy: .public)")
    }

    /// Caps HLS variant selection to the user's preferred quality.
    ///
    /// The resolver now hands back a master playlist for most videos rather than a single
    /// progressive stream, and a master playlist advertises YouTube's whole variant ladder. Without
    /// a ceiling AVPlayer's ABR logic is free to climb past the user's setting — previously the
    /// height cap was applied when picking a progressive format, so this keeps that preference
    /// meaningful. It also shortens time-to-first-frame, since AVPlayer no longer pulls a large
    /// segment before reporting `.readyToPlay`. `.auto` stays uncapped so ABR can use the full
    /// ladder, and this is a no-op for progressive and local-file candidates.
    // MARK: - Quality and readiness

    func applyQualityCap(to item: AVPlayerItem) {
        applyQualityCap(to: item, quality: playbackQuality)
    }

    /// Reapply the adaptive cap when Settings changes without replacing the current item.
    func refreshPlaybackQualityLimits() {
        guard let item = player.currentItem else { return }
        applyQualityCap(to: item)
    }

    func applyQualityCap(to item: AVPlayerItem, quality: VideoQuality) {
        PlayerQualityPolicy.apply(
            to: item,
            quality: quality,
            cellularQuality: preferences.cellularPlaybackQuality
        )
    }

    func readinessTimeout(for strategy: PlaybackStrategy) -> Duration {
        switch strategy {
        case .b5iIOS, .b5iTVHTML5:
            return .seconds(4)
        case .localFile, .native, .nativePaired, .nativeProgressive:
            return .seconds(12)
        }
    }

}
