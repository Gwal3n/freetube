import Foundation
import AVFoundation
import OSLog
import SwiftData
import UIKit

/// CLAUDE.md §8: single source of truth for playback. Injected via SwiftUI environment.
/// Mini player and full-screen player both observe this object — neither owns its own `AVPlayer`.
/// Domain extensions keep transport operations separate; queue, playlist, recommendation, and
/// SponsorBlock collaborators own their own state and lifetimes.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerStateManager {
    enum LoadState: Equatable {
        case idle
        case resolving
        /// A candidate URL is installed in the player and `play()` has already been issued, but
        /// `AVPlayerItem` hasn't reported `.readyToPlay` yet.
        ///
        /// Split out from `.resolving` for the startup-perception pass: both states paint the
        /// video's thumbnail rather than a spinner, but once we're buffering there is nothing
        /// left to "prepare" — the mini-player can show the real artwork and channel name
        /// instead of a placeholder glyph and "Preparing…". Keeping it distinct from
        /// `.downloading(progress:phase:)` also means the download chrome (percentage label +
        /// determinate bar) stays reserved for actual file transfers.
        case buffering
        /// File is being fetched. `progress` is 0…1 when known, nil during yt-dlp's mux/merge phase.
        /// `phase` labels which stream is in flight ("video", "audio", "stream") so the UI can show
        /// "Downloading video 42%" instead of two confusing identical bars in a row.
        case downloading(progress: Double?, phase: String?)
        case readyToPlay
        case failed(String)
    }

    // MARK: - Published state

    private(set) var currentVideo: Video?
    /// Cached artwork for the current video. Populates `MPNowPlayingInfoCenter` (lock-screen +
    /// Control Center) and `PlayerArtworkBackdrop`, which paints it into the video area for as long
    /// as AVPlayer has no frame to show. Refreshed when the current video changes.
    private(set) var currentArtwork: UIImage?
    var loadState: LoadState = .idle
    var isPlaying: Bool = false
    /// True only when the current item reached its natural end and no automatic transition has
    /// replaced it. Drives replay chrome and lets a backward seek resume from the chosen point.
    var hasEnded: Bool = false
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    /// Actual loaded ranges can be discontinuous, especially for HLS. Keep each range separate
    /// so the timeline never suggests that an unbuffered gap is ready to play.
    var bufferedRanges: [ClosedRange<TimeInterval>] = []
    /// The newest contiguous DVR window offered by the current live AVPlayerItem. Unlike a
    /// video's duration, this range moves forward as the broadcast advances.
    var liveSeekableRange: ClosedRange<TimeInterval>?
    /// Native frame stepping is not available for every item, notably some HLS streams. Ready
    /// on-demand video still offers a fine-seek fallback rather than hiding the control.
    var canStepFrameBackward: Bool {
        guard case .readyToPlay = loadState,
              currentVideo?.isLive != true,
              !isAudioOnly,
              player.currentItem != nil,
              duration.isFinite,
              duration > 0 else { return false }
        return (pendingSeekTarget ?? elapsed) > 0
    }

    var canStepFrameForward: Bool {
        guard case .readyToPlay = loadState,
              currentVideo?.isLive != true,
              !isAudioOnly,
              player.currentItem != nil,
              duration.isFinite,
              duration > 0 else { return false }
        return (pendingSeekTarget ?? elapsed) < duration
    }
    var playbackRate: Double
    /// Actual requested transport rate, capped at 2x until a ready item supports fast-forward.
    var effectivePlaybackRate: Double
    var isPreparingFastPlayback = false
    var fastPlaybackPreparation: FastPlaybackLocalFileService.ProgressUpdate?
    var playbackQuality: VideoQuality
    private(set) var sleepTimerOption: SleepTimerOption = .off
    var isAudioOnly: Bool { playbackQuality == .audioOnly }
    var isSwitchingAudioMode = false
    var videoQualityBeforeAudio: VideoQuality
    private(set) var isMuted = false
    var sponsorBlockNotice: SponsorBlockNotice? { sponsorBlockCoordinator.notice }
    var sponsorBlockSegments: [SponsorBlockSegment] { sponsorBlockCoordinator.segments }
    var chapters: [VideoChapter] = []
    var youtubeChapters: [VideoChapter] = []
    var storyboard: VideoStoryboard?
    /// Source tracks from the accepted playback response; signed URLs remain memory-only.
    var captionTracks: [VideoCaptionTrack] = []
    private(set) var commentsCountText: String?
    var isLoadingMoreRecommendations: Bool { recommendations.isLoadingMore }
    var activePlaylist: Playlist? { playlistContext.playlist }
    var activePlaylistOrigin: PlaylistPlaybackOrigin? { playlistContext.origin }
    /// Increments for each actual video load so late History playlist lookups cannot attach to a
    /// different playback, even if the user opens the same video again from another surface.
    private(set) var playbackSessionID = 0
    var isLoadingMorePlaylistVideos: Bool { playlistContext.isLoadingMore }
    var playlistRecommendations: [Video] { recommendations.playlistItems }
    /// Explicit user choices are independent from disposable recommendations and playlists.
    var manualQueue: [Video] { manualQueueController.items }
    var queueNotice: PlayerManualQueueController.Notice? { manualQueueController.notice }
    /// Display-correct dimensions reported by AVPlayerItem after its tracks become ready.
    var videoPresentationSize: CGSize = .zero
    /// Monotonic request consumed by PlayerSurface to end an existing automatic PiP session when
    /// the user explicitly reopens the expanded player.
    private(set) var pipDismissalRequest = 0
    /// Monotonic request consumed by `SwiftUIPlayerContainer`. Playback commands request an
    /// expansion instead of setting presentation state directly, giving the container a chance to
    /// stage its SwiftUI artwork before the UIKit video surface begins moving.
    var playerExpansionRequest = 0
    /// Allows the fixed collapse control to use the container's video-only shrinking transition.
    var playerCollapseRequest = 0
    @ObservationIgnored var pendingCollapseCompletion: (sessionID: Int, action: () -> Void)?
    /// Width of the in-app floating video; optionally restored between launches. The view
    /// constrains it to the current viewport.
    var floatingMiniPlayerWidth: CGFloat = 216
    /// The visible thumbnail that initiated the next explicit expansion, in screen coordinates.
    /// This is presentation-only state; it never changes playback or persists with a video.
    var launchSourceFrame: CGRect?
    @ObservationIgnored var pendingLaunchSource: (videoID: String, frame: CGRect)?
    var miniPlayerVisible: Bool = false
    var fullScreenPresented: Bool = false
    /// Shared with the SwiftUI presentation container so its global drag pauses while the chapter
    /// panel owns vertical gestures.
    var chapterListPresented: Bool = false
    /// Current bottom edge of the *visible* video surface in expanded-player coordinates. A
    /// raised playlist panel can cover part of the video; its scroll must never collapse the
    /// player even when the gesture begins within the video's original frame.
    var expandedPlayerSurfaceHeight: CGFloat = 0
    var playlistPanelPresented: Bool = false
    var playerPanelAtTop: Bool = true
    /// Disabled while the in-place portrait fullscreen mode owns the entire viewport.
    var playerPresentationGestureEnabled: Bool = true
    /// Only in-place portrait fullscreen may extend the player into the status-bar area.
    /// Playlist browsing must keep the normal inset.
    var portraitPlayerFullscreenActive: Bool = false
    /// True only after the outer SwiftUI container has accepted a downward collapse drag. The
    /// details ScrollView pauses for that gesture so its rubber band cannot move metadata faster
    /// than the player surface that contains it.
    var playerPresentationGestureActive: Bool = false

    func removeFromUpNext(videoID: String) {
        if activePlaylist != nil {
            recommendations.removeFromPlaylistItems(videoID: videoID)
        } else if let index = queue.items.firstIndex(where: { $0.id == videoID }),
                  index != queue.currentIndex {
            queue.remove(at: index)
        }
    }

    // MARK: - AVPlayer

    /// `AVQueuePlayer` to unlock `advanceToNextItem()` and queue introspection for future preload.
    /// IMPORTANT: don't use `replaceCurrentItem(with:)` to load tracks — it's a no-op on
    /// `AVQueuePlayer` when the internal queue is empty (which is our usual state). Use the
    /// `removeAllItems()` + `insert(_:after:)` pattern via `swap(to:)` below.
    let player = AVQueuePlayer()

    // MARK: - Collaborators

    let queue: QueueManager
    let resolver: any PlaybackResolving
    let itemFactory = PlaybackItemFactory()
    @ObservationIgnored let fastPlaybackCandidatePreparer = PlayerFastPlaybackCandidatePreparer()
    let preparationGate = PlayerItemPreparationGate()
    let readinessGate = PlayerItemReadinessGate()
    let sponsorBlockCoordinator: PlayerSponsorBlockCoordinator
    private let manualQueueController = PlayerManualQueueController()
    let recommendations: PlayerRecommendationController
    let playlistContext: PlayerPlaylistContext
    let preferences: UserPreferences
    let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")

    /// Sticky "this queue accepts recommendations" intent. Set to `true` whenever the user loads
    /// a standalone video and `false` for curated Play all / Shuffle all batches. Drives:
    ///   1. The per-load `fillQueueWithRecommendations` call in `resolveAndPlay`.
    ///   2. The auto-advance dead-end recovery in `playNext()` — when the queue runs out and
    ///      repeat is off, we fire a fresh recs fetch using the queue's last item as a seed,
    ///      then advance once new items land. Each standalone load replaces the old queue, so
    ///      these refills never retain previously played videos.
    var queueAcceptsRecommendations = true

    /// Separate from recommendations so Previous/Next can revisit explicit selections.
    var playbackHistory = PlayerPlaybackHistory()
    private let watchHistory = PlayerWatchHistoryTracker()

    var canPlayPrevious: Bool { playbackHistory.canMoveBackward }
    var canPlayNext: Bool {
        playbackHistory.hasForwardEntry
            || !manualQueue.isEmpty
            || queue.availableUpcomingCount(limit: 1) > 0
    }

    @ObservationIgnored let observations = PlayerObservationStore()
    weak var acceptedStreamItem: AVPlayerItem?
    var acceptedStreamStrategy: PlaybackStrategy?
    /// One post-start resolver pass per video. A second terminal failure is shown to the user
    /// instead of repeatedly rebuilding the player on an unusable network/source.
    var didAttemptPlaybackRecovery = false
    /// Explicit transport intent survives AVPlayer autonomously pausing a failed item. `isPlaying`
    /// is an observation/prediction for chrome and may already be false when failure KVO arrives.
    var wantsPlayback = false

    var itemLoadStartedAt: Date?
    let itemDiagnostics = PlayerItemDiagnostics()
    @ObservationIgnored var fastPlayback = PlayerFastPlaybackState()
    var pendingSeekTarget: TimeInterval?
    /// The active video track's observed cadence, retained across pause. HLS does not always
    /// expose a track, so fine seeking falls back to a conservative 30 fps estimate.
    @ObservationIgnored var observedFrameRate: (item: AVPlayerItem, fps: Double)?
    var seekRequestID = 0
    var audioModeSwitchGeneration = 0
    var resumeAfterAudioSwitch: Bool?
    private var sleepTimerTask: Task<Void, Never>?
    var audioInterruptionObserver: NSObjectProtocol?
    var interruptedPlaybackSessionID: Int?
    init(
        queue: QueueManager = QueueManager(),
        resolver: any PlaybackResolving = PlaybackResolver(),
        sponsorBlockService: any SponsorBlockServicing = SponsorBlockService(),
        videoService: any VideoServicing = VideoService(),
        playlistService: any PlaylistServicing = PlaylistService(),
        preferences: UserPreferences = UserPreferences()
    ) {
        self.queue = queue
        self.resolver = resolver
        self.sponsorBlockCoordinator = PlayerSponsorBlockCoordinator(service: sponsorBlockService)
        self.recommendations = PlayerRecommendationController(
            queue: queue, videoService: videoService, preferences: preferences
        )
        self.playlistContext = PlayerPlaylistContext(queue: queue, service: playlistService)
        self.preferences = preferences
        self.playbackRate = PlaybackSpeedPresets.bounded(preferences.defaultPlaybackRate)
        self.effectivePlaybackRate = PlaybackSpeedPresets.supportedRate(preferences.defaultPlaybackRate, canPlayFastForward: false)
        FastPlaybackLocalFileService.removeOrphansAtLaunch()
        NativeHLSDownloadService.removeOrphansAtLaunch()
        self.playbackQuality = preferences.preferredQuality
        self.videoQualityBeforeAudio = preferences.preferredQuality == .audioOnly
            ? .auto : preferences.preferredQuality
        if preferences.rememberFloatingPlayerPlacement {
            let savedWidth = preferences.savedFloatingPlayerWidth
            self.floatingMiniPlayerWidth = savedWidth.isFinite
                ? min(420, max(120, CGFloat(savedWidth))) : 216
        }
        // AVQueuePlayer defaults to `.advance`, which removes the finished item before our
        // end-of-playback UI can replay or seek it. We manage queue transitions ourselves in the
        // end observer, so pause on the final frame and retain the item until that decision is
        // made. This is also what keeps the video surface from turning black at natural end.
        player.actionAtItemEnd = .pause
        // The app is intentionally read-only and currently has no caption picker. AVPlayer can
        // otherwise auto-select a matching HLS legible track from the device language settings,
        // making captions appear with no corresponding UI state or way to dismiss them.
        player.appliesMediaSelectionCriteriaAutomatically = false
        // Keep the audio track running when the player view goes off-screen (popup minimize, app
        // backgrounded). Without this, AVPlayer pauses video tracks as soon as their pixel buffer
        // pipeline is no longer visible, which manifests as "audio cuts out the moment you collapse
        // the mini-player." Pairs with the `.playback` AVAudioSession configured at launch.
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        // Must stay `true`, which is also the default — this is spelled out because setting it
        // to `false` looks like the obvious way to make the optimistic start in `resolveAndPlay`
        // start sooner, and it does the exact opposite.
        //
        // `resolveAndPlay` calls `play()` the moment a candidate URL is installed, while the item
        // is still `.unknown`. `AVPlayer.rate` ignores a nonzero rate set before the current item
        // is ready to play, so the *only* thing that makes that early request survive to readiness
        // is this property: with `true` the player enters `.waitingToPlayAtSpecifiedRate` and
        // begins on its own the instant the item is ready. With `false` there is no such holding
        // state, the request is dropped on the floor, and playback never starts — the video sits
        // on its thumbnail until the user pauses and plays again.
        player.automaticallyWaitsToMinimizeStalling = true
        // High rates are validated per item. Do not optimistically start an unknown HLS item at
        // a persisted 3x–5x rate; it may enter silent, keyframe-only fast-forward playback.
        player.defaultRate = Float(effectivePlaybackRate)
        installObservers()
    }

    /// Tear-down hook for tests / app lifecycle. Call before releasing the manager. We avoid `deinit`
    /// here so we don't have to reach into main-actor-isolated state from a nonisolated context.
    func tearDownObservers() {
        resetFastPlaybackState()
        setSleepTimer(.off)
        playerPresentationTask?.cancel()
        playerPresentationTask = nil
        audioModeSwitchTask?.cancel()
        audioModeSwitchTask = nil
        audioModeSwitchGeneration &+= 1
        isSwitchingAudioMode = false
        resumeAfterAudioSwitch = nil
        observations.clearAll(on: player)
        if let audioInterruptionObserver { NotificationCenter.default.removeObserver(audioInterruptionObserver) }
        audioInterruptionObserver = nil
        interruptedPlaybackSessionID = nil
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        wantsPlayback = false
        bufferedRanges = []
        liveSeekableRange = nil
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendations.resetPager()
        playlistContext.clear()
        recommendations.clearPlaylistItems()
        videoPresentationSize = .zero
    }

    // MARK: - Public commands

    /// Play a local file already on disk — used by the **Link** tab's completed downloads.
    ///
    /// **Why a separate entry point and not `load(video:)`:** the YouTube-shaped resolver in
    /// `resolveAndPlay` calls `DownloadManager.ensureDownloaded` which keys off `videoID` and
    /// looks for `Documents/<id>.mp4`. URL-fetched files live under `Documents/<title>.mp4`
    /// and don't have a YouTube `videoID`, so threading them
    /// through the normal path would either crash or silently re-trigger a yt-dlp download.
    /// This method skips resolution entirely — the file is already there, just play it.
    ///
    /// **What we skip vs the normal load path:** watch-history upsert (URL files aren't in
    /// the YouTube `WatchHistoryEntry` schema), queue recommendation fill (no related-video
    /// surface for arbitrary URLs), and `ensureDownloaded` (file is on disk).
    /// **What we keep:** `currentVideo` (synthetic so the mini-player title/subtitle still
    /// render), `miniPlayerVisible` flipped true so the SwiftUI mini-player appears, NowPlayingCenter
    /// update for lock-screen artwork, and the standard observe/loadItem flow so errors and
    /// playback state still surface through the existing UI.
    func loadLocalFile(at fileURL: URL, title: String, source: String?, thumbnailURL: URL?) {
        log.info("loadLocalFile path=\(fileURL.path, privacy: .public) title=\"\(title, privacy: .public)\"")
        playbackSessionID &+= 1
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        resetFastPlaybackState()
        if sleepTimerOption == .endOfVideo { setSleepTimer(.off) }
        // Link downloads are independent of the YouTube quality preference. An audio file keeps
        // its artwork visible; a video file keeps its actual frames visible.
        playbackQuality = ["m4a", "mp3", "aac", "opus", "ogg", "wav", "flac"]
            .contains(fileURL.pathExtension.lowercased()) ? .audioOnly : .auto
        // A YouTube resolution still in flight would otherwise keep testing candidates against a
        // player we're about to hand a local file, and its readiness wait would sit out its full
        // timeout. Cancelling settles that wait immediately.
        resolutionTask?.cancel()
        audioModeSwitchTask?.cancel()
        audioModeSwitchGeneration &+= 1
        isSwitchingAudioMode = false
        resumeAfterAudioSwitch = nil
        recommendations.cancel()
        contentPrefetchTask?.cancel()
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendations.resetPager()
        playlistContext.clear()
        recommendations.clearPlaylistItems()
        videoPresentationSize = .zero
        if isPlaying { pause() }
        if !player.items().isEmpty { player.removeAllItems() }

        // Synthetic Video so the existing mini-player + FullScreenPlayer chrome (which read
        // `currentVideo` everywhere) work without conditional branches. Channel name reuses
        // the extractor ("YouTube", "Vimeo", …) — closest analogue for arbitrary URLs.
        let synthetic = Video(
            id: "fetch-" + UUID().uuidString,
            title: title,
            channelID: "",
            channelName: source ?? "Link",
            channelThumbnailURL: nil,
            thumbnailURL: thumbnailURL,
            duration: nil,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
        currentVideo = synthetic
        // Bypass the queue's YouTube-related tracking — URL files don't participate in the
        // recommendation chain. setCurrent appends to the queue dataset for upcoming-up UI;
        // we just zero it for arbitrary files.
        queueAcceptsRecommendations = false
        presentPlayer(for: synthetic.id, expanded: true)
        elapsed = 0
        duration = 0
        observations.clearLoadedTimeRanges()
        bufferedRanges = []
        liveSeekableRange = nil
        hasEnded = false
        pendingSeekTarget = nil
        seekRequestID += 1
        refreshArtwork(for: synthetic)

        let item = AVPlayerItem(url: fileURL)
        loadItem(item)
        loadState = .readyToPlay
        updateNowPlaying()
        play()
    }

    /// Loads a video for playback and opens the expanded player for direct selections.
    ///
    /// - Parameter skipRecommendations: when `true`, suppresses the post-play "fill queue with
    ///   YouTube recommendations" call. Pass this from explicit batch actions that already
    ///   populated a curated queue — playlist's Play all / Shuffle all — so the user's queue
    ///   stays exactly what they chose. Default is `false` so single-video taps from Home /
    ///   Search / Mini-player still get the YouTube-app-style autoplay chain.
    /// - Parameter expandPlayer: when `true`, opens the popup immediately. Automatic queue
    ///   transitions pass `false` so a user who collapsed the player is not pulled back into it.
    /// - Parameter preservePlaylistPosition: plays a manual-queue item between playlist videos
    ///   without adding it to the playlist or advancing the playlist's current position.
    func load(
        _ video: Video,
        autoplay: Bool = true,
        skipRecommendations: Bool = false,
        expandPlayer: Bool = true,
        recordInPlaybackHistory: Bool = true,
        localFileURL: URL? = nil,
        preservePlaylistPosition: Bool = false
    ) {
        log.info("load(\(video.id, privacy: .public)) autoplay=\(autoplay, privacy: .public) skipRecs=\(skipRecommendations, privacy: .public)")
        if localFileURL == nil, currentVideo?.id == video.id {
            if case .failed = loadState {
                // A deliberate second tap retries a failed resolution.
            } else {
                log.info("load: current video selected again; expanding without restarting playback")
                if expandPlayer {
                    presentPlayer(for: video.id, expanded: true)
                }
                return
            }
        }
        playbackSessionID &+= 1
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        resetFastPlaybackState()
        log.info("Playback speed for new video: default=\(self.playbackRate, privacy: .public)x")
        if sleepTimerOption == .endOfVideo { setSleepTimer(.off) }
        // Settings can change while the player is alive. Adopt that choice for the next video,
        // without disturbing the stream currently playing when the preference changes.
        let preferredQuality = preferences.preferredQuality
        if playbackQuality != preferredQuality {
            playbackQuality = preferredQuality
            if preferredQuality != .audioOnly { videoQualityBeforeAudio = preferredQuality }
        }
        manualQueueController.remove(video.id)
        persistCurrentPlaybackProgress(force: true)
        resolutionTask?.cancel()
        audioModeSwitchTask?.cancel()
        audioModeSwitchGeneration &+= 1
        isSwitchingAudioMode = false
        resumeAfterAudioSwitch = nil
        recommendations.cancel()
        contentPrefetchTask?.cancel()
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendations.resetPager()
        videoPresentationSize = .zero
        let isPlaylistInterlude = preservePlaylistPosition && skipRecommendations && activePlaylist != nil
        if recordInPlaybackHistory {
            playbackHistory.record(.init(
                video: video,
                skipRecommendations: skipRecommendations,
                preservesPlaylistPosition: isPlaylistInterlude
            ))
        }
        queueAcceptsRecommendations = !skipRecommendations
        if skipRecommendations, activePlaylist != nil {
            recommendations.clearPlaylistItems()
        }
        if !skipRecommendations {
            playlistContext.clear()
            recommendations.clearPlaylistItems()
        }
        // Pause and tear down anything currently playing. Otherwise we'd keep streaming audio from
        // the previous video while the new one's file is downloading — which is what the user kept
        // hearing when they tapped "next" mid-download.
        if isPlaying {
            log.info("load: pausing current playback before resolving new video")
            pause()
        }
        wantsPlayback = autoplay
        if !player.items().isEmpty {
            log.debug("load: clearing AVQueuePlayer items (\(self.player.items().count, privacy: .public) entries)")
            player.removeAllItems()
        }
        currentVideo = video
        watchHistory.reset()
        // Ordinary playback gets a fresh, bounded recommendation set for each video and retains no
        // history. Explicit playlist batches keep their curated order and skip recommendations.
        if skipRecommendations {
            if !isPlaylistInterlude {
                queue.setCurrent(video)
            }
        } else {
            queue.replace(with: [video])
        }
        watchHistory.recordOnOpen(
            video,
            recordsHistory: preferences.recordsWatchHistory,
            addWhenOpened: preferences.addToHistoryWhenOpened,
            playlist: queue.current?.id == video.id ? activePlaylist : nil,
            playlistOrigin: activePlaylistOrigin
        )
        presentPlayer(for: video.id, expanded: expandPlayer)
        loadState = .resolving
        // Wipe transport state from the previous video so a stray time-observer tick during the
        // transition (the periodic callback can fire AFTER currentVideo flips but BEFORE the new
        // AVPlayerItem is installed) doesn't carry the old item's elapsed/duration into a save —
        // that's what showed phantom progress bars on cells the user never played.
        elapsed = 0
        duration = 0
        observations.clearLoadedTimeRanges()
        bufferedRanges = []
        liveSeekableRange = nil
        hasEnded = false
        pendingSeekTarget = nil
        seekRequestID += 1
        refreshArtwork(for: video)
        loadSponsorBlockSegments(for: video.id)
        resolutionTask = Task { [weak self] in
            await self?.resolveAndPlay(
                video: video,
                autoplay: autoplay,
                skipRecommendations: skipRecommendations,
                localFileURL: localFileURL
            )
        }
    }

    /// Replaces the lightweight metadata used to start direct-URL playback. Stream resolution is
    /// intentionally left untouched: the ID is already resolving, and metadata must never restart
    /// or delay that path.
    func enrichCurrentVideo(with video: Video) {
        guard currentVideo?.id == video.id else { return }
        currentVideo = video
        queue.updateVideo(video)
        playbackHistory.updateCurrentVideo(video)
        refreshArtwork(for: video)
        watchHistory.updateMetadataIfRecorded(video, recordsHistory: preferences.recordsWatchHistory)
        updateNowPlaying()
    }

    /// Applies ancillary metadata only while it still belongs to the selected video. Stream
    /// resolution and the current AVPlayerItem are deliberately untouched.
    func installVideoDetails(_ info: VideoInfo, for videoID: String) {
        guard let current = currentVideo, current.id == videoID else { return }
        // Direct links begin with intentionally cheap placeholder metadata. If that first lookup
        // fails, the shared MoreVideoInfos request still supplies the title and uploader later;
        // merge those fields without restarting playback or touching the resolved stream.
        if !info.video.title.isEmpty,
           (current.title == "YouTube video" || current.title.isEmpty || current.channelID.isEmpty) {
            // Browse and /next titles may be translated. Once the playback response supplied
            // videoDetails.title, a later watch-page details response must not replace it.
            let needsTitle = current.title == "YouTube video" || current.title.isEmpty
            enrichCurrentVideo(with: Video(
                id: current.id,
                title: needsTitle ? info.video.title : current.title,
                channelID: info.video.channelID.isEmpty ? current.channelID : info.video.channelID,
                channelName: info.video.channelName.isEmpty ? current.channelName : info.video.channelName,
                channelThumbnailURL: info.video.channelThumbnailURL ?? current.channelThumbnailURL,
                thumbnailURL: current.thumbnailURL ?? info.video.thumbnailURL,
                duration: current.duration ?? info.video.duration,
                viewCount: current.viewCount ?? info.video.viewCount,
                publishedAt: current.publishedAt ?? info.video.publishedAt,
                publishedRelative: current.publishedRelative ?? info.video.publishedRelative,
                descriptionSnippet: info.descriptionText ?? current.descriptionSnippet,
                isLive: current.isLive || info.video.isLive,
                isShort: current.isShort || info.video.isShort
            ))
        } else if info.video.isLive && !current.isLive {
            // Search/feed rows do not always carry a live badge. A watch-page count explicitly
            // marked live can confirm the stream without replacing its already-correct identity.
            enrichCurrentVideo(with: current.markedLive())
        }
        if !info.chapters.isEmpty {
            youtubeChapters = info.chapters
            updateDisplayedChapters()
        }
        if let resolvedStoryboard = info.storyboard {
            storyboard = resolvedStoryboard
        }
        if let count = info.commentsCountText, !count.isEmpty {
            commentsCountText = count
        }
    }

    var resolutionTask: Task<Void, Never>?
    var audioModeSwitchTask: Task<Void, Never>?
    var contentPrefetchTask: Task<Void, Never>?
    var playerPresentationTask: Task<Void, Never>?

    func play() {
        if hasEnded {
            replay()
            return
        }
        log.info("play()")
        wantsPlayback = true
        AudioSessionConfigurator.configure(
            allowMixing: preferences.allowAudioMixing,
            activate: true
        )
        applyEffectivePlaybackRate()
        player.play()
        isPlaying = true
        // A temporary hold must not become the persisted default speed. `play()` begins at the
        // base rate, so apply the temporary override immediately after that normal start.
        if fastPlayback.temporaryRate != nil, player.currentItem?.status == .readyToPlay {
            player.rate = Float(effectivePlaybackRate)
        }
        if isSwitchingAudioMode, resumeAfterAudioSwitch != nil {
            resumeAfterAudioSwitch = true
        }
        if fastPlayback.isInstalling { fastPlayback.resumeAfterSwitch = true }
        publishNowPlayingWhenAlone()
        reconcilePlaybackRate()
    }

    /// A user-requested retry keeps the selected video, queue, active playlist, and presentation.
    /// It starts a new resolver session, unlike `load(_:)`, which deliberately resets those states.
    func retryFailedPlayback() {
        guard case .failed = loadState,
              let video = currentVideo, !video.id.hasPrefix("fetch-") else { return }

        playbackSessionID &+= 1
        let recovery = playbackRecovery(for: video, excluding: nil, resumeFromHistoryIfUnstarted: true)
        log.info("Retrying failed playback for \(video.id, privacy: .public)")
        resolutionTask?.cancel()
        cancelFastPlaybackPreparation()
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        wantsPlayback = true
        player.pause()
        isPlaying = false
        player.removeAllItems()
        loadState = .resolving
        updateNowPlaying()

        resolutionTask = Task { [weak self] in
            await StreamURLCache.shared.removeAll(videoID: video.id)
            guard !Task.isCancelled, let self,
                  self.playbackSessionID == recovery.sessionID,
                  self.currentVideo?.id == video.id else { return }
            await self.resolveAndPlay(video: video, autoplay: false, recovery: recovery)
        }
    }

    func pause() {
        log.info("pause()")
        wantsPlayback = false
        interruptedPlaybackSessionID = nil
        player.pause()
        isPlaying = false
        if isSwitchingAudioMode, resumeAfterAudioSwitch != nil {
            resumeAfterAudioSwitch = false
        }
        if fastPlayback.isInstalling { fastPlayback.resumeAfterSwitch = false }
        persistCurrentPlaybackProgress(force: true)
    }

    func togglePlayPause() {
        log.info("togglePlayPause() (isPlaying=\(self.isPlaying, privacy: .public))")
        isPlaying ? pause() : play()
    }

    func requestInlinePlaybackRestoration() {
        pipDismissalRequest &+= 1
    }

    /// Restarts the current item without resolving its stream again.
    func replay() {
        guard player.currentItem != nil else { return }
        log.info("replay()")
        wantsPlayback = true
        hasEnded = false
        seek(to: 0, resumeAfterEnded: false)
        player.play()
        isPlaying = true
        publishNowPlayingWhenAlone()
        reconcilePlaybackRate()
    }

    /// Inserts a user-selected search result immediately after the current queue item without
    /// interrupting playback. The queue remains local and recommendation loading stays unchanged.
    func enqueueNext(_ video: Video) {
        guard let currentVideo,
              manualQueueController.enqueueNext(video, currentVideoID: currentVideo.id) else { return }
        log.info("Queued \(video.id, privacy: .public) to play next")
    }

    func enqueue(_ video: Video) {
        guard manualQueueController.enqueue(video, currentVideoID: currentVideo?.id) else { return }
        log.info("Added \(video.id, privacy: .public) to manual queue")
    }

    /// Plays an explicit queue choice without turning a playlist interlude into a new standalone
    /// recommendation session. Both the Next button and a tapped queue row use this path.
    func playManualQueueItem(_ video: Video, expandPlayer: Bool = true) {
        guard manualQueue.contains(where: { $0.id == video.id }) else { return }
        manualQueueController.remove(video.id)
        let interruptsPlaylist = activePlaylist != nil
        if interruptsPlaylist {
            log.info("Playing manual queue interlude; preserving playlist index=\(self.queue.currentIndex, privacy: .public)")
        }
        load(
            video,
            skipRecommendations: interruptsPlaylist,
            expandPlayer: expandPlayer,
            preservePlaylistPosition: interruptsPlaylist
        )
    }

    func removeFromManualQueue(videoID: String) {
        manualQueueController.remove(videoID)
    }

    func removeFromManualQueueWithUndo(videoID: String) {
        manualQueueController.removeWithUndo(videoID)
    }

    func clearManualQueue() {
        manualQueueController.clear()
    }

    func clearManualQueueWithUndo() {
        manualQueueController.clearWithUndo()
    }

    func moveManualQueue(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        manualQueueController.move(fromOffsets: offsets, toOffset: destination)
    }

    func showQueueNotice(message: String, undoAction: (() -> Void)? = nil, haptic: Bool = true) {
        manualQueueController.showNotice(message: message, undoAction: undoAction, haptic: haptic)
    }

    func undoQueueNotice() {
        manualQueueController.undoNotice()
    }

    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
        log.info("Player muted=\(self.isMuted, privacy: .public)")
    }

    /// Changes this player's loudness relative to the device volume. Unmute when the user
    /// explicitly raises it; the system output level remains owned by iOS.
    func setPlaybackVolume(_ volume: Float) {
        let boundedVolume = min(1, max(0, volume))
        player.volume = boundedVolume
        if isMuted && boundedVolume > 0 {
            isMuted = false
            player.isMuted = false
        }
    }

    var isLoopingCurrentVideo: Bool {
        queue.repeatMode == .one
    }

    func toggleLoopCurrentVideo() {
        queue.repeatMode = queue.repeatMode == .one ? .off : .one
        log.info("Loop current video=\(self.queue.repeatMode == .one, privacy: .public)")
    }

    /// Stops playback once after a duration or at the selected video's natural end. Timed
    /// choices survive video changes; end-of-video is cancelled when that video is replaced.
    /// Neither choice survives player dismissal or app relaunch.
    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerOption = currentVideo == nil ? .off : option
        guard let duration = sleepTimerOption.duration else { return }
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.sleepTimerOption == option else { return }
            self.pause()
            self.setSleepTimer(.off)
        }
    }

    func dismiss() {
        log.info("dismiss()")
        interruptedPlaybackSessionID = nil
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        wantsPlayback = false
        resetFastPlaybackState()
        setSleepTimer(.off)
        persistCurrentPlaybackProgress(force: true)
        resolutionTask?.cancel()
        resolutionTask = nil
        audioModeSwitchTask?.cancel()
        audioModeSwitchTask = nil
        audioModeSwitchGeneration &+= 1
        isSwitchingAudioMode = false
        resumeAfterAudioSwitch = nil
        playerPresentationTask?.cancel()
        playerPresentationTask = nil
        pendingLaunchSource = nil
        launchSourceFrame = nil
        recommendations.cancel()
        contentPrefetchTask?.cancel()
        contentPrefetchTask = nil
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        recommendations.resetPager()
        playlistContext.clear()
        playbackSessionID &+= 1
        recommendations.clearPlaylistItems()
        pause()
        miniPlayerVisible = false
        fullScreenPresented = false
        chapterListPresented = false
        expandedPlayerSurfaceHeight = 0
        playlistPanelPresented = false
        playerPanelAtTop = true
        playerPresentationGestureEnabled = true
        portraitPlayerFullscreenActive = false
        playerPresentationGestureActive = false
        currentVideo = nil
        loadState = .idle
        hasEnded = false
        player.removeAllItems()
        if let localFileURL = fastPlayback.localFileURL {
            fastPlayback.localFileURL = nil
            FastPlaybackLocalFileService.remove(localFileURL)
        }
        observations.clearLoadedTimeRanges()
        bufferedRanges = []
        liveSeekableRange = nil
        playbackHistory.reset()
        NowPlayingCenter.clear()
    }

    func finishPlaybackSetup(video: Video, skipRecommendations: Bool) {
        log.info("resolveAndPlay: finished happy-path for \(video.id, privacy: .public)")
        // Fire-and-forget queue fill — uses YouTube's `/next` (WEB) endpoint, independent of the
        // resolver's `/player` (IOS) endpoint, so it can't interfere with playback that's already
        // running. Failures are logged but never surface to the user; queue stays as-is on error.
        //
        // Suppressed only when the caller explicitly asks (playlist's Play all / Shuffle all).
        // Every other entry point — single video taps from Home/Search/Mini-player, queue-row
        // taps, Next/Previous, and even tapping an individual playlist video — gets the
        // autoplay-style recommendation fill, so the player keeps advancing past the seed.
        if !skipRecommendations || activePlaylist != nil {
            scheduleRecommendationFill(for: video)
        }
    }

    func scheduleRecommendationFill(for seed: Video) {
        recommendations.scheduleFill(
            for: seed,
            isCurrent: { [weak self] in self?.currentVideo?.id == seed.id },
            isPlaylistActive: { [weak self] in self?.activePlaylist != nil },
            onDetails: { [weak self] info in self?.installVideoDetails(info, for: seed.id) }
        )
    }

    func fillQueueWithRecommendations(for seed: Video) async {
        await recommendations.fill(
            for: seed,
            isCurrent: { [weak self] in self?.currentVideo?.id == seed.id },
            isPlaylistActive: { [weak self] in self?.activePlaylist != nil },
            onDetails: { [weak self] info in self?.installVideoDetails(info, for: seed.id) }
        )
    }

    var canLoadMoreRecommendations: Bool {
        recommendations.canLoadMore
    }

    func loadMoreRecommendations() async {
        await recommendations.loadMore(
            currentVideoID: { [weak self] in self?.currentVideo?.id },
            isPlaylistActive: { [weak self] in self?.activePlaylist != nil }
        )
    }

    // MARK: - Resume position

    /// Resumes only meaningful, unfinished progress. A short opening is treated as unwatched, and
    /// the final 30 seconds are treated as completed so finished videos restart normally.
    func applyStoredResumePosition(
        _ progress: (position: TimeInterval, duration: TimeInterval)?,
        for video: Video
    ) {
        guard let position = storedResumePosition(progress, for: video) else { return }
        log.info("Resuming \(video.id, privacy: .public) at \(position, privacy: .public)s")
        seek(to: position)
    }

    func storedResumePosition(
        _ progress: (position: TimeInterval, duration: TimeInterval)?,
        for video: Video
    ) -> TimeInterval? {
        watchHistory.resumePosition(
            progress,
            for: video.id,
            currentVideoID: currentVideo?.id,
            duration: duration,
            recordsProgress: preferences.recordsWatchProgress
        )
    }

    /// Writes at most every ten seconds during playback, plus forced lifecycle saves. Duplicate
    /// pause/dismiss/video-switch calls are suppressed when the position has not advanced.
    func persistCurrentPlaybackProgress(force: Bool) {
        let video = currentVideo
        watchHistory.persist(
            video: video,
            elapsed: elapsed,
            duration: duration,
            force: force,
            recordsHistory: preferences.recordsWatchHistory,
            recordsProgress: preferences.recordsWatchProgress,
            playlist: queue.current?.id == video?.id ? activePlaylist : nil,
            playlistOrigin: activePlaylistOrigin
        )
    }

    func accumulateHistoryPlaybackTime() {
        watchHistory.accumulatePlaybackTime(
            isPlaying: player.timeControlStatus == .playing,
            recordsHistory: preferences.recordsWatchHistory
        )
    }

    /// A mixable session should not compete for Now Playing while another app is active. When the
    /// user starts or resumes FreeTube while it is the only audio source, reactivating the same
    /// mixable configuration and republishing metadata lets it present normal media controls.
    private func publishNowPlayingWhenAlone() {
        guard preferences.allowAudioMixing,
              !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
        AudioSessionConfigurator.configure(allowMixing: true, activate: true)
        log.info("Publishing Now Playing for FreeTube as the only active audio source")
        updateNowPlaying()
    }

    /// Resolves an artwork image for the given video and stores it in `currentArtwork`. Tries three
    /// sources in order:
    ///  1. Kingfisher's in-memory cache for the video's `thumbnailURL` (synchronous → no flicker).
    ///  2. `DownloadsStore`'s xattr-stored compressed thumbnail (for videos played from the Downloads tab,
    ///     where the constructed `Video` has `thumbnailURL == nil`).
    ///  3. Async network/disk fetch through Kingfisher.
    /// Clears artwork immediately so the previous video's preview doesn't linger on the lock screen.
    private func refreshArtwork(for video: Video) {
        currentArtwork = nil
        let immediate = PlayerArtworkResolver.immediateArtwork(for: video)
        if let artwork = immediate.image {
            currentArtwork = artwork
            updateNowPlaying()
        }
        guard immediate.needsNetworkLookup else { return }
        PlayerArtworkResolver.retrieveArtwork(for: video) { [weak self, videoID = video.id] image in
            Task { @MainActor in
                guard let self else { return }
                // Drop the result if the user switched videos while the fetch was inflight.
                guard self.currentVideo?.id == videoID else { return }
                self.currentArtwork = image
                self.updateNowPlaying()
            }
        }
    }
}
