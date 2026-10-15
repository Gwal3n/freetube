import Foundation
import AVFoundation
import Combine
import Kingfisher
import OSLog
import SwiftData
import UIKit

/// CLAUDE.md §8: single source of truth for playback. Injected via SwiftUI environment.
/// Mini player and full-screen player both observe this object — neither owns its own `AVPlayer`.
///
/// Combine is used **only** here for `AVPlayer` time-observer bridging, per CLAUDE.md §2.9.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerStateManager {
    struct QueueNotice: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let offersUndo: Bool
    }
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
    private(set) var loadState: LoadState = .idle
    private(set) var isPlaying: Bool = false
    /// True only when the current item reached its natural end and no automatic transition has
    /// replaced it. Drives replay chrome and lets a backward seek resume from the chosen point.
    private(set) var hasEnded: Bool = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Actual loaded ranges can be discontinuous, especially for HLS. Keep each range separate
    /// so the timeline never suggests that an unbuffered gap is ready to play.
    private(set) var bufferedRanges: [ClosedRange<TimeInterval>] = []
    /// The newest contiguous DVR window offered by the current live AVPlayerItem. Unlike a
    /// video's duration, this range moves forward as the broadcast advances.
    private(set) var liveSeekableRange: ClosedRange<TimeInterval>?
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
    private(set) var playbackRate: Double
    /// Actual requested transport rate, capped at 2x until a ready item supports fast-forward.
    private(set) var effectivePlaybackRate: Double
    private(set) var isPreparingFastPlayback = false
    private(set) var fastPlaybackPreparation: FastPlaybackLocalFileService.ProgressUpdate?
    private(set) var playbackQuality: VideoQuality
    private(set) var sleepTimerOption: SleepTimerOption = .off
    var isAudioOnly: Bool { playbackQuality == .audioOnly }
    private(set) var isSwitchingAudioMode = false
    private var videoQualityBeforeAudio: VideoQuality
    private(set) var isMuted = false
    private(set) var sponsorBlockNotice: SponsorBlockNotice?
    private(set) var sponsorBlockSegments: [SponsorBlockSegment] = []
    private(set) var chapters: [VideoChapter] = []
    private var youtubeChapters: [VideoChapter] = []
    private var communityChapters: [VideoChapter] = []
    private(set) var storyboard: VideoStoryboard?
    /// Source tracks from the accepted playback response; signed URLs remain memory-only.
    private(set) var captionTracks: [VideoCaptionTrack] = []
    private(set) var commentsCountText: String?
    private(set) var isLoadingMoreRecommendations = false
    private(set) var activePlaylist: Playlist?
    private(set) var activePlaylistOrigin: PlaylistPlaybackOrigin?
    /// Increments for each actual video load so late History playlist lookups cannot attach to a
    /// different playback, even if the user opens the same video again from another surface.
    private(set) var playbackSessionID = 0
    private(set) var isLoadingMorePlaylistVideos = false
    private(set) var playlistRecommendations: [Video] = []
    /// Explicit user choices are independent from disposable recommendations and playlists.
    private(set) var manualQueue: [Video]
    private(set) var queueNotice: QueueNotice?
    /// Display-correct dimensions reported by AVPlayerItem after its tracks become ready.
    private(set) var videoPresentationSize: CGSize = .zero
    /// Monotonic request consumed by PlayerSurface to end an existing automatic PiP session when
    /// the user explicitly reopens the expanded player.
    private(set) var pipDismissalRequest = 0
    /// Monotonic request consumed by `SwiftUIPlayerContainer`. Playback commands request an
    /// expansion instead of setting presentation state directly, giving the container a chance to
    /// stage its SwiftUI artwork before the UIKit video surface begins moving.
    private(set) var playerExpansionRequest = 0
    /// Allows the fixed collapse control to use the container's video-only shrinking transition.
    private(set) var playerCollapseRequest = 0
    /// Width of the in-app floating video; optionally restored between launches. The view
    /// constrains it to the current viewport.
    private(set) var floatingMiniPlayerWidth: CGFloat = 216
    /// The visible thumbnail that initiated the next explicit expansion, in screen coordinates.
    /// This is presentation-only state; it never changes playback or persists with a video.
    private(set) var launchSourceFrame: CGRect?
    @ObservationIgnored private var pendingLaunchSource: (videoID: String, frame: CGRect)?
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
            playlistRecommendations.removeAll { $0.id == videoID }
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
    private let resolver: any PlaybackResolving
    private let itemFactory = PlaybackItemFactory()
    private let preparationGate = PlayerItemPreparationGate()
    private let readinessGate = PlayerItemReadinessGate()
    private let sponsorBlockService: any SponsorBlockServicing
    private let sponsorBlockCoordinator = PlayerSponsorBlockCoordinator()
    private let videoService: any VideoServicing
    private let playlistService: any PlaylistServicing
    private let preferences: UserPreferences
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")

    /// Sticky "this queue accepts recommendations" intent. Set to `true` whenever the user loads
    /// a standalone video and `false` for curated Play all / Shuffle all batches. Drives:
    ///   1. The per-load `fillQueueWithRecommendations` call in `resolveAndPlay`.
    ///   2. The auto-advance dead-end recovery in `playNext()` — when the queue runs out and
    ///      repeat is off, we fire a fresh recs fetch using the queue's last item as a seed,
    ///      then advance once new items land. Each standalone load replaces the old queue, so
    ///      these refills never retain previously played videos.
    private var queueAcceptsRecommendations = true

    /// Separate from recommendations so Previous/Next can revisit explicit selections.
    private var playbackHistory = PlayerPlaybackHistory()
    private let watchHistory = PlayerWatchHistoryTracker()

    var canPlayPrevious: Bool { playbackHistory.canMoveBackward }
    var canPlayNext: Bool {
        playbackHistory.hasForwardEntry
            || !manualQueue.isEmpty
            || queue.availableUpcomingCount(limit: 1) > 0
    }

    private var timeObserver: Any?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemPresentationSizeObservation: NSKeyValueObservation?
    private var itemLoadedTimeRangesObservation: NSKeyValueObservation?
    private var itemFailedToEndObservation: NSObjectProtocol?
    private weak var acceptedStreamItem: AVPlayerItem?
    private var acceptedStreamStrategy: PlaybackStrategy?
    /// One post-start resolver pass per video. A second terminal failure is shown to the user
    /// instead of repeatedly rebuilding the player on an unusable network/source.
    private var didAttemptPlaybackRecovery = false
    /// Explicit transport intent survives AVPlayer autonomously pausing a failed item. `isPlaying`
    /// is an observation/prediction for chrome and may already be false when failure KVO arrives.
    private var wantsPlayback = false

    private var itemLoadStartedAt: Date?
    private var itemErrorLogObservation: NSObjectProtocol?
    private var itemAccessLogObservation: NSObjectProtocol?
    private let itemDiagnostics = PlayerItemDiagnostics()
    private var playerErrorObservation: NSKeyValueObservation?
    private var fastPlaybackTask: Task<Void, Never>?
    private var fastPlaybackTimeoutTask: Task<Void, Never>?
    private var fastPlaybackGeneration = 0
    private var fastPlaybackFailed = false
    private var fastPlaybackUserRequested = false
    private var fastPlaybackLocalFileURL: URL?
    private var isInstallingFastPlayback = false
    private var resumeAfterFastPlaybackSwitch: Bool?
    private var temporaryPlaybackRate: Double?
    private var wasPlayingBeforeTemporaryRate: Bool?
    private var sponsorBlockTask: Task<Void, Never>?
    private var sponsorBlockNoticeTask: Task<Void, Never>?
    private var pendingSeekTarget: TimeInterval?
    /// The active video track's observed cadence, retained across pause. HLS does not always
    /// expose a track, so fine seeking falls back to a conservative 30 fps estimate.
    @ObservationIgnored private var observedFrameRate: (item: AVPlayerItem, fps: Double)?
    private var seekRequestID = 0
    private var audioModeSwitchGeneration = 0
    private var resumeAfterAudioSwitch: Bool?
    private var sleepTimerTask: Task<Void, Never>?
    private var recommendationBacklog: [Video] = []
    private var recommendationContinuationToken: String?
    private var playlistContinuationToken: String?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var interruptedPlaybackSessionID: Int?
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
        self.sponsorBlockService = sponsorBlockService
        self.videoService = videoService
        self.playlistService = playlistService
        self.preferences = preferences
        self.manualQueue = PlayerManualQueueStore.restore()
        self.playbackRate = PlaybackSpeedPresets.bounded(preferences.defaultPlaybackRate)
        self.effectivePlaybackRate = PlaybackSpeedPresets.supportedRate(preferences.defaultPlaybackRate, canPlayFastForward: false)
        FastPlaybackLocalFileService.removeOrphansAtLaunch()
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
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        itemStatusObservation?.invalidate()
        itemPresentationSizeObservation?.invalidate()
        itemLoadedTimeRangesObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let audioInterruptionObserver { NotificationCenter.default.removeObserver(audioInterruptionObserver) }
        audioInterruptionObserver = nil
        interruptedPlaybackSessionID = nil
        if let itemFailedToEndObservation { NotificationCenter.default.removeObserver(itemFailedToEndObservation) }
        if let itemErrorLogObservation { NotificationCenter.default.removeObserver(itemErrorLogObservation) }
        if let itemAccessLogObservation { NotificationCenter.default.removeObserver(itemAccessLogObservation) }
        timeObserver = nil
        endObserver = nil
        itemFailedToEndObservation = nil
        acceptedStreamItem = nil
        acceptedStreamStrategy = nil
        didAttemptPlaybackRecovery = false
        wantsPlayback = false
        itemErrorLogObservation = nil
        itemAccessLogObservation = nil
        itemStatusObservation = nil
        itemPresentationSizeObservation = nil
        itemLoadedTimeRangesObservation = nil
        bufferedRanges = []
        liveSeekableRange = nil
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendationBacklog = []
        recommendationContinuationToken = nil
        isLoadingMoreRecommendations = false
        activePlaylist = nil
        activePlaylistOrigin = nil
        playlistRecommendations = []
        playlistContinuationToken = nil
        isLoadingMorePlaylistVideos = false
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
        recommendationTask?.cancel()
        contentPrefetchTask?.cancel()
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendationBacklog = []
        recommendationContinuationToken = nil
        isLoadingMoreRecommendations = false
        activePlaylist = nil
        activePlaylistOrigin = nil
        playlistRecommendations = []
        playlistContinuationToken = nil
        isLoadingMorePlaylistVideos = false
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
        itemLoadedTimeRangesObservation?.invalidate()
        itemLoadedTimeRangesObservation = nil
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
        if manualQueue.contains(where: { $0.id == video.id }) {
            manualQueue = PlayerManualQueueStore.removing(video.id, from: manualQueue)
            persistManualQueue()
        }
        persistCurrentPlaybackProgress(force: true)
        resolutionTask?.cancel()
        audioModeSwitchTask?.cancel()
        audioModeSwitchGeneration &+= 1
        isSwitchingAudioMode = false
        resumeAfterAudioSwitch = nil
        recommendationTask?.cancel()
        contentPrefetchTask?.cancel()
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        commentsCountText = nil
        recommendationBacklog = []
        recommendationContinuationToken = nil
        isLoadingMoreRecommendations = false
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
            playlistRecommendations = []
        }
        if !skipRecommendations {
            activePlaylist = nil
            activePlaylistOrigin = nil
            playlistRecommendations = []
            playlistContinuationToken = nil
            isLoadingMorePlaylistVideos = false
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
        itemLoadedTimeRangesObservation?.invalidate()
        itemLoadedTimeRangesObservation = nil
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

    private var resolutionTask: Task<Void, Never>?
    private var audioModeSwitchTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?
    private var contentPrefetchTask: Task<Void, Never>?
    private var queueNoticeDismissTask: Task<Void, Never>?
    private var queueNoticeUndoAction: (() -> Void)?
    private var playerPresentationTask: Task<Void, Never>?

    /// Called by a tapped video row before `load` so the player can grow from that thumbnail.
    /// A video ID guards against a stale row gesture launching a different queued item.
    func prepareLaunch(for videoID: String, from frame: CGRect) {
        guard frame.width > 20, frame.height > 20,
              frame.width.isFinite, frame.height.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite else {
            pendingLaunchSource = nil
            return
        }
        pendingLaunchSource = (videoID, frame)
    }

    func finishLaunchPresentation() {
        launchSourceFrame = nil
    }

    func requestPlayerCollapse() {
        playerCollapseRequest &+= 1
    }

    func resizeFloatingMiniPlayer(to width: CGFloat) {
        guard width.isFinite else { return }
        floatingMiniPlayerWidth = width
        if preferences.rememberFloatingPlayerPlacement {
            preferences.savedFloatingPlayerWidth = Double(width)
        }
    }

    /// Stages one frame at the tapped thumbnail before expansion. `AVPlayerViewController` does
    /// not reliably participate in a SwiftUI insertion transition; the mounted surface must have
    /// a real starting frame. Actions without a thumbnail retain the floating-window fallback.
    private func presentPlayer(for videoID: String, expanded: Bool) {
        playerPresentationTask?.cancel()
        let source = pendingLaunchSource?.videoID == videoID ? pendingLaunchSource?.frame : nil
        pendingLaunchSource = nil
        let wasVisible = miniPlayerVisible
        miniPlayerVisible = true
        guard expanded else {
            launchSourceFrame = nil
            return
        }

        // Already expanded: changing the current item must not replay the presentation animation.
        guard !fullScreenPresented else {
            launchSourceFrame = nil
            return
        }

        launchSourceFrame = source

        if wasVisible && source == nil {
            playerExpansionRequest &+= 1
            return
        }

        fullScreenPresented = false
        playerPresentationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled,
                  let self,
                  self.miniPlayerVisible,
                  self.currentVideo?.id == videoID else { return }
            self.playerExpansionRequest &+= 1
        }
    }

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
        if temporaryPlaybackRate != nil, player.currentItem?.status == .readyToPlay {
            player.rate = Float(effectivePlaybackRate)
        }
        if isSwitchingAudioMode, resumeAfterAudioSwitch != nil {
            resumeAfterAudioSwitch = true
        }
        if isInstallingFastPlayback { resumeAfterFastPlaybackSwitch = true }
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
        if isInstallingFastPlayback { resumeAfterFastPlaybackSwitch = false }
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
        guard let currentVideo, video.id != currentVideo.id,
              !VideoBlocklist.shared.blocks(video) else { return }
        manualQueue = PlayerManualQueueStore.insertingNext(video, into: manualQueue)
        persistManualQueue()
        showQueueNotice(message: "Playing next")
        log.info("Queued \(video.id, privacy: .public) to play next")
    }

    func enqueue(_ video: Video) {
        guard video.id != currentVideo?.id,
              !VideoBlocklist.shared.blocks(video),
              !manualQueue.contains(where: { $0.id == video.id }) else { return }
        manualQueue = PlayerManualQueueStore.appending(video, to: manualQueue)
        persistManualQueue()
        showQueueNotice(message: "Added to queue")
        log.info("Added \(video.id, privacy: .public) to manual queue")
    }

    /// Plays an explicit queue choice without turning a playlist interlude into a new standalone
    /// recommendation session. Both the Next button and a tapped queue row use this path.
    func playManualQueueItem(_ video: Video, expandPlayer: Bool = true) {
        guard manualQueue.contains(where: { $0.id == video.id }) else { return }
        manualQueue = PlayerManualQueueStore.removing(video.id, from: manualQueue)
        persistManualQueue()
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
        manualQueue = PlayerManualQueueStore.removing(videoID, from: manualQueue)
        persistManualQueue()
    }

    func removeFromManualQueueWithUndo(videoID: String) {
        guard let index = manualQueue.firstIndex(where: { $0.id == videoID }) else { return }
        let removedVideo = manualQueue.remove(at: index)
        persistManualQueue()
        showQueueNotice(message: "Removed") { [weak self] in
            guard let self, !self.manualQueue.contains(where: { $0.id == removedVideo.id }) else { return }
            self.manualQueue = PlayerManualQueueStore.restoring(removedVideo, at: index, to: self.manualQueue)
            self.persistManualQueue()
        }
    }

    func clearManualQueue() {
        guard !manualQueue.isEmpty else { return }
        manualQueue.removeAll()
        persistManualQueue()
    }

    func clearManualQueueWithUndo() {
        guard !manualQueue.isEmpty else { return }
        let removedVideos = manualQueue
        manualQueue.removeAll()
        persistManualQueue()
        showQueueNotice(message: "Queue cleared") { [weak self] in
            guard let self else { return }
            self.manualQueue = PlayerManualQueueStore.restoring(removedVideos, to: self.manualQueue)
            self.persistManualQueue()
        }
    }

    func moveManualQueue(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let reordered = PlayerManualQueueStore.reordered(
            manualQueue,
            fromOffsets: offsets,
            toOffset: destination,
            isBlocked: { VideoBlocklist.shared.blocks($0) }
        ) else { return }
        manualQueue = reordered
        persistManualQueue()
    }

    private func showQueueNotice(message: String, undoAction: (() -> Void)? = nil, haptic: Bool = true) {
        let notice = QueueNotice(message: message, offersUndo: undoAction != nil)
        queueNotice = notice
        queueNoticeUndoAction = undoAction
        if haptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        queueNoticeDismissTask?.cancel()
        let displayDuration: Duration = undoAction == nil ? .seconds(1.4) : .seconds(2)
        queueNoticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled, self?.queueNotice?.id == notice.id else { return }
            self?.queueNotice = nil
            self?.queueNoticeUndoAction = nil
        }
    }

    func undoQueueNotice() {
        guard let action = queueNoticeUndoAction else { return }
        queueNoticeDismissTask?.cancel()
        queueNoticeUndoAction = nil
        queueNotice = nil
        action()
    }

    func setPlaybackRate(_ rate: Double) {
        let boundedRate = PlaybackSpeedPresets.bounded(rate)
        log.info("Playback speed selected: \(boundedRate, privacy: .public)x")
        playbackRate = boundedRate
        // The player menu changes this video only. Settings owns the saved default; writing
        // menu choices there made subsequent HLS videos start at a capped 2x after a 3x choice.
        if boundedRate > 2 {
            fastPlaybackUserRequested = true
            if !isPreparingFastPlayback { fastPlaybackFailed = false }
        }
        reconcilePlaybackRate()
        if let item = player.currentItem, item.status == .readyToPlay {
            log.info("Playback speed applied: selected=\(self.playbackRate, privacy: .public)x effective=\(self.effectivePlaybackRate, privacy: .public)x actual=\(self.player.rate, privacy: .public)x canPlayFastForward=\(item.canPlayFastForward, privacy: .public) pitch=\(item.audioTimePitchAlgorithm, privacy: .public)")
        }
    }

    /// Hold and menu speeds share the same capability checks and progressive-source experiment.
    /// Releasing a hold cancels unresolved work without changing the user's saved base speed.
    func beginTemporaryPlaybackRate(_ rate: Double) {
        guard temporaryPlaybackRate == nil, !hasEnded,
              loadState == .readyToPlay,
              player.currentItem?.status == .readyToPlay else { return }
        wasPlayingBeforeTemporaryRate = isPlaying
        temporaryPlaybackRate = PlaybackSpeedPresets.bounded(rate)
        reconcilePlaybackRate()
        if !isPlaying { play() }
    }

    func endTemporaryPlaybackRate() {
        guard temporaryPlaybackRate != nil else { return }
        let restorePaused = wasPlayingBeforeTemporaryRate == false
        temporaryPlaybackRate = nil
        wasPlayingBeforeTemporaryRate = nil
        reconcilePlaybackRate()
        if restorePaused { pause() }
    }

    private var requestedTransportRate: Double { temporaryPlaybackRate ?? playbackRate }

    /// Never send an unsupported HLS rate to AVPlayer. A paused, invisible probe prepares the
    /// alternative first, leaving the current video audible and seekable at up to 2x meanwhile.
    private func reconcilePlaybackRate() {
        applyEffectivePlaybackRate()
        guard requestedTransportRate > 2 else {
            if !isInstallingFastPlayback { cancelFastPlaybackPreparation() }
            return
        }
        // A hold must not start a potentially large temporary download. A saved high-speed
        // preference also waits for an explicit tap on each new online video.
        guard temporaryPlaybackRate == nil, fastPlaybackUserRequested else { return }
        guard let item = player.currentItem, item.status == .readyToPlay,
              !item.canPlayFastForward, loadState == .readyToPlay,
              !hasEnded, !isSwitchingAudioMode, !isPreparingFastPlayback, !fastPlaybackFailed,
              let video = currentVideo else { return }
        guard !video.isLive, !video.id.hasPrefix("fetch-") else {
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            return
        }
        isPreparingFastPlayback = true
        fastPlaybackPreparation = .init(phase: .resolving, completedBytes: 0, totalBytes: nil)
        fastPlaybackGeneration &+= 1
        let generation = fastPlaybackGeneration
        let session = playbackSessionID
        let quality = playbackQuality
        log.info("Fast playback experiment started for \(video.id, privacy: .public) requested=\(self.requestedTransportRate, privacy: .public)x")
        fastPlaybackTask = Task { [weak self] in
            await self?.prepareFastPlayback(for: video, quality: quality, originalItem: item, session: session, generation: generation)
        }
        scheduleFastPlaybackTimeout(after: .seconds(30), generation: generation)
    }

    private func scheduleFastPlaybackTimeout(after duration: Duration, generation: Int) {
        fastPlaybackTimeoutTask?.cancel()
        fastPlaybackTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.fastPlaybackGeneration == generation,
                  !self.isInstallingFastPlayback else { return }
            self.log.notice("Fast playback extraction/preparation timed out")
            self.cancelFastPlaybackPreparation()
            self.failFastPlayback(message: "Higher speeds are unavailable for this video")
        }
    }

    private func applyEffectivePlaybackRate() {
        let item = player.currentItem
        let supportsFastPlayback = item?.status == .readyToPlay && item?.canPlayFastForward == true
        effectivePlaybackRate = PlaybackSpeedPresets.supportedRate(requestedTransportRate, canPlayFastForward: supportsFastPlayback)
        let baseRate = Float(PlaybackSpeedPresets.supportedRate(playbackRate, canPlayFastForward: supportsFastPlayback))
        if player.defaultRate != baseRate { player.defaultRate = baseRate }
        if supportsFastPlayback, requestedTransportRate > 2, item?.audioTimePitchAlgorithm != .timeDomain {
            // Time-domain pitch correction is designed for voice and supports these rates.
            // Keep it for the item's lifetime rather than rebuilding processing on every hold.
            item?.audioTimePitchAlgorithm = .timeDomain
        }
        if isPlaying, !isInstallingFastPlayback, player.rate != Float(effectivePlaybackRate) {
            player.rate = Float(effectivePlaybackRate)
        }
    }

    private func cancelFastPlaybackPreparation() {
        fastPlaybackGeneration &+= 1
        fastPlaybackTask?.cancel()
        fastPlaybackTask = nil
        fastPlaybackTimeoutTask?.cancel()
        fastPlaybackTimeoutTask = nil
        isPreparingFastPlayback = false
        fastPlaybackPreparation = nil
    }

    func cancelPendingFastPlayback() {
        guard isPreparingFastPlayback else { return }
        cancelFastPlaybackPreparation()
        fastPlaybackFailed = true
        fastPlaybackUserRequested = false
        temporaryPlaybackRate = nil
        wasPlayingBeforeTemporaryRate = nil
        if playbackRate > 2 {
            playbackRate = 2
        }
        applyEffectivePlaybackRate()
        log.info("Fast playback preparation cancelled by user")
    }

    private func resetFastPlaybackState() {
        cancelFastPlaybackPreparation()
        isInstallingFastPlayback = false
        resumeAfterFastPlaybackSwitch = nil
        fastPlaybackFailed = false
        fastPlaybackUserRequested = false
        temporaryPlaybackRate = nil
        wasPlayingBeforeTemporaryRate = nil
        playbackRate = PlaybackSpeedPresets.bounded(preferences.defaultPlaybackRate)
        effectivePlaybackRate = PlaybackSpeedPresets.supportedRate(playbackRate, canPlayFastForward: false)
    }

    private func failFastPlayback(message: String) {
        fastPlaybackFailed = true
        fastPlaybackUserRequested = false
        fastPlaybackPreparation = nil
        if playbackRate > 2 {
            playbackRate = 2
        }
        applyEffectivePlaybackRate()
        showQueueNotice(message: message, haptic: false)
    }

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
                let resume = resumeAfterFastPlaybackSwitch == true
                player.pause()
                isInstallingFastPlayback = false
                loadItem(originalItem)
                let position = switchPosition ?? elapsed
                player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600))
                pendingSeekTarget = nil
                loadState = .readyToPlay
                if resume { play() }
            }
            if let preparedLocalFile, fastPlaybackLocalFileURL != preparedLocalFile {
                FastPlaybackLocalFileService.remove(preparedLocalFile)
            }
            if fastPlaybackGeneration == generation {
                fastPlaybackTask = nil
                fastPlaybackTimeoutTask?.cancel()
                fastPlaybackTimeoutTask = nil
                isPreparingFastPlayback = false
                fastPlaybackPreparation = nil
                isInstallingFastPlayback = false
                resumeAfterFastPlaybackSwitch = nil
            }
        }
        let replacement: AVPlayerItem
        do {
            let candidate = try await resolver.resolveForFastPlayback(video: video, quality: quality)
            try Task.checkCancellation()
            let itemToProbe: AVPlayerItem
            switch candidate.source {
            case .direct, .localFile:
                itemToProbe = try await itemFactory.makeItem(for: candidate)
            case .composite(let videoURL, let audioURL):
                // Remote AVCompositions stalled on device. Materialize their tracks in a
                // cancellable temporary file while the existing HLS item keeps playing.
                scheduleFastPlaybackTimeout(after: .seconds(1_200), generation: generation)
                log.info("Preparing temporary local file for fast playback of \(video.id, privacy: .public): workingDuration=\(originalItem.duration.seconds, privacy: .public)s videoMetadataDuration=\(video.duration ?? -1, privacy: .public)s")
                let localFile = try await FastPlaybackLocalFileService.prepare(
                    videoURL: videoURL, audioURL: audioURL,
                    referenceDuration: originalItem.duration.seconds
                ) { [weak self] update in
                    guard let self, self.fastPlaybackGeneration == generation,
                          self.playbackSessionID == session else { return }
                    self.fastPlaybackPreparation = update
                }
                preparedLocalFile = localFile
                itemToProbe = AVPlayerItem(url: localFile)
            }
            try Task.checkCancellation()
            let preparation = FastPlaybackPreparation(item: itemToProbe)
            let preparedAsset = try await preparation.prepare(audioOnly: quality == .audioOnly)
            try Task.checkCancellation()
            // Never insert the probe's AVPlayerItem into the visible AVQueuePlayer. The two
            // players may still overlap internally after detachment and AVFoundation throws an
            // uncaught Objective-C exception if they are given the same item.
            replacement = AVPlayerItem(asset: preparedAsset)
            replacement.audioTimePitchAlgorithm = .timeDomain
        } catch {
            guard !Task.isCancelled, fastPlaybackGeneration == generation,
                  playbackSessionID == session else { return }
            // Keep signed stream URLs out of diagnostics. Error type + code distinguish
            // transfer, export and probe failures without logging NSError userInfo.
            log.notice("Fast playback candidate rejected before swap: \(PlayerItemReadinessGate.describe(itemError: error), privacy: .public) type=\(String(reflecting: type(of: error)), privacy: .public)")
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            return
        }
        guard !Task.isCancelled, fastPlaybackGeneration == generation,
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
        resumeAfterFastPlaybackSwitch = isPlaying
        isInstallingFastPlayback = true
        fastPlaybackTimeoutTask?.cancel()
        player.pause()
        pendingSeekTarget = position
        seekRequestID += 1
        loadState = .buffering
        itemLoadStartedAt = Date()
        loadItem(replacement)
        installedReplacement = replacement
        let readiness = await readinessGate.wait(for: replacement, timeout: .seconds(12))
        guard !Task.isCancelled, fastPlaybackGeneration == generation,
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
            guard !Task.isCancelled, fastPlaybackGeneration == generation, playbackSessionID == session,
                  player.currentItem === replacement else { return }
            pendingSeekTarget = nil
            loadState = .readyToPlay
            applyEffectivePlaybackRate()
            if resumeAfterFastPlaybackSwitch == true { play() } else { isPlaying = false }
            fastPlaybackLocalFileURL = preparedLocalFile
            replacementAccepted = true
            log.info("Fast progressive playback accepted: source=\(preparedLocalFile == nil ? "direct" : "temporary-local", privacy: .public) requested=\(self.requestedTransportRate, privacy: .public)x effective=\(self.effectivePlaybackRate, privacy: .public)x actual=\(self.player.rate, privacy: .public)x canPlayFastForward=\(replacement.canPlayFastForward, privacy: .public) pitch=\(replacement.audioTimePitchAlgorithm, privacy: .public)")
        } else {
            log.notice("Fast playback swap rejected; restoring original stream")
            loadItem(originalItem)
            videoPresentationSize = previousSize
            await seekForSourceSwitch(to: pendingSeekTarget ?? position, item: originalItem)
            guard !Task.isCancelled, fastPlaybackGeneration == generation, playbackSessionID == session,
                  player.currentItem === originalItem else { return }
            pendingSeekTarget = nil
            loadState = .readyToPlay
            failFastPlayback(message: "Higher speeds are unavailable for this video")
            if resumeAfterFastPlaybackSwitch == true { play() } else { isPlaying = false }
        }
        updateNowPlaying()
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

    /// Updates the HLS adaptive-quality ceiling in place and persists it for future resolutions.
    /// Fixed progressive/local assets cannot switch representation after loading, but retain the
    /// new preference for the next video without disrupting current playback.
    func setPlaybackQuality(_ quality: VideoQuality) {
        guard quality != playbackQuality, !isInstallingFastPlayback else { return }
        cancelFastPlaybackPreparation()
        fastPlaybackFailed = false
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
            fastPlaybackFailed = false
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

    private func seekForSourceSwitch(to seconds: TimeInterval, item: AVPlayerItem) async {
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
        activePlaylist = details.playlist
        activePlaylistOrigin = origin
        playlistRecommendations = []
        playlistContinuationToken = details.continuationToken
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
        recommendationTask?.cancel()
        recommendationTask = nil
        recommendationBacklog = []
        recommendationContinuationToken = nil
        playlistRecommendations = []
        queue.isShuffleOn = false
        queue.replace(with: visibleVideos, startAt: index)
        if let currentVideo { queue.updateVideo(currentVideo) }
        queueAcceptsRecommendations = false
        activePlaylist = details.playlist
        activePlaylistOrigin = origin
        playlistContinuationToken = details.continuationToken
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
        recommendationTask?.cancel()
        recommendationTask = nil

        let suggestions = playlistRecommendations.filter {
            $0.id != currentVideo.id && !VideoBlocklist.shared.blocks($0)
        }
        activePlaylist = nil
        activePlaylistOrigin = nil
        playlistRecommendations = []
        playlistContinuationToken = nil
        isLoadingMorePlaylistVideos = false
        queueAcceptsRecommendations = true
        recommendationBacklog = []
        recommendationContinuationToken = nil
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
        recommendationTask = Task { [weak self] in
            await self?.fillQueueWithRecommendations(for: currentVideo)
        }
    }

    var canLoadMorePlaylistItems: Bool {
        activePlaylist != nil && playlistContinuationToken != nil
    }

    func loadMorePlaylistItems() async {
        guard let token = playlistContinuationToken, !isLoadingMorePlaylistVideos else { return }
        let playlistID = activePlaylist?.id
        isLoadingMorePlaylistVideos = true
        defer { isLoadingMorePlaylistVideos = false }
        do {
            let page = try await playlistService.fetchMore(continuation: token)
            guard activePlaylist?.id == playlistID else { return }
            let existing = Set(queue.items.map(\.id))
            queue.append(contentsOf: page.videos.filter {
                !existing.contains($0.id) && !VideoBlocklist.shared.blocks($0)
            })
            playlistContinuationToken = page.continuationToken
        } catch {
            log.notice("Playlist continuation failed: \(String(describing: error), privacy: .public)")
        }
    }

    var isLoadingMoreQueueItems: Bool {
        isLoadingMorePlaylistVideos || isLoadingMoreRecommendations
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
        recommendationTask?.cancel()
        recommendationTask = nil
        contentPrefetchTask?.cancel()
        contentPrefetchTask = nil
        clearSponsorBlockState()
        clearChapterState()
        storyboard = nil
        captionTracks = []
        recommendationBacklog = []
        recommendationContinuationToken = nil
        isLoadingMoreRecommendations = false
        activePlaylist = nil
        activePlaylistOrigin = nil
        playbackSessionID &+= 1
        playlistRecommendations = []
        playlistContinuationToken = nil
        isLoadingMorePlaylistVideos = false
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
        if let fastPlaybackLocalFileURL {
            self.fastPlaybackLocalFileURL = nil
            FastPlaybackLocalFileService.remove(fastPlaybackLocalFileURL)
        }
        itemLoadedTimeRangesObservation?.invalidate()
        itemLoadedTimeRangesObservation = nil
        bufferedRanges = []
        liveSeekableRange = nil
        playbackHistory.reset()
        NowPlayingCenter.clear()
    }

    func undoSponsorBlockSkip() {
        guard let notice = sponsorBlockNotice else { return }
        sponsorBlockNoticeTask?.cancel()
        sponsorBlockNotice = nil
        // Undo is the one rewind that should not immediately trigger the same skip again.
        seek(to: notice.originalStartTime, rearmSponsorBlock: false)
    }

    func confirmSponsorBlockSkip() {
        guard let notice = sponsorBlockNotice,
              case .prompt(let endTime) = notice.kind else { return }
        sponsorBlockNoticeTask?.cancel()
        sponsorBlockNotice = nil
        seek(to: endTime)
    }

    func dismissSponsorBlockNotice() {
        sponsorBlockNoticeTask?.cancel()
        sponsorBlockNotice = nil
    }

    // MARK: - Internals

    private func loadSponsorBlockSegments(for videoID: String) {
        guard preferences.sponsorBlockEnabled else { return }
        let categories = preferences.sponsorBlockCategories
        guard !categories.isEmpty else { return }
        sponsorBlockTask = Task { [weak self] in
            guard let self else { return }
            do {
                let segments = try await sponsorBlockService.fetchSegments(
                    videoID: videoID,
                    categories: categories
                )
                try Task.checkCancellation()
                guard currentVideo?.id == videoID else { return }
                installSponsorBlockObservers(for: segments)
                let fullLabels = segments.filter(\.isFullVideoLabel).count
                log.info("SponsorBlock loaded \(segments.count, privacy: .public) segments (full labels=\(fullLabels, privacy: .public)) for \(videoID, privacy: .public)")
            } catch is CancellationError {
                log.debug("SponsorBlock lookup cancelled for \(videoID, privacy: .public)")
            } catch {
                // SponsorBlock is an optional enhancement. Network or decoding failures must never
                // interrupt playback or surface as a player failure.
                log.notice("SponsorBlock lookup failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func installSponsorBlockObservers(for segments: [SponsorBlockSegment]) {
        sponsorBlockSegments = segments
        var chapterStarts = Set<TimeInterval>()
        communityChapters = segments.compactMap { segment in
            guard segment.category == .chapter,
                  let title = segment.title,
                  chapterStarts.insert(segment.startTime).inserted else { return nil }
            return VideoChapter(
                title: title, startTime: segment.startTime,
                timeDescription: nil, thumbnailURL: nil
            )
        }
        updateDisplayedChapters()

        sponsorBlockCoordinator.installBoundaryObservers(
            on: player,
            for: segments,
            shouldObserve: { [weak self] in self?.shouldObserveSponsorBlockSegment($0) ?? false },
            onEntry: { [weak self] in self?.handleSponsorBlockSegment($0) }
        )

        // A highlight is a point to jump *to*, not a duration to skip once playback reaches it.
        // Offer it as soon as the lookup finishes while leaving Show only as a marker-only mode.
        if let highlight = segments.first(where: {
            $0.category == .highlight
                && preferences.sponsorBlockBehavior(for: $0.category) == .ask
                && elapsed < $0.startTime - 0.5
        }) {
            sponsorBlockCoordinator.markHandled(highlight.id)
            sponsorBlockNotice = SponsorBlockNotice(
                category: .highlight,
                originalStartTime: elapsed,
                kind: .prompt(endTime: highlight.startTime)
            )
            scheduleSponsorBlockNoticeDismissal()
        }

        // The lookup may finish after playback has already entered a segment. Boundary observers
        // cannot fire retroactively, so evaluate the current position once immediately.
        if let current = segments.first(where: {
            shouldObserveSponsorBlockSegment($0)
                && elapsed >= $0.startTime && elapsed < $0.endTime
        }) {
            handleSponsorBlockSegment(current, enteredAt: elapsed)
        }
    }

    private func shouldObserveSponsorBlockSegment(_ segment: SponsorBlockSegment) -> Bool {
        sponsorBlockCoordinator.shouldObserve(
            segment,
            behavior: preferences.sponsorBlockBehavior(for: segment.category),
            minimumSkipSeconds: preferences.sponsorBlockMinimumSkipSeconds
        )
    }

    private func handleSponsorBlockSegment(at time: TimeInterval) {
        guard let segment = sponsorBlockSegments.first(where: {
            shouldObserveSponsorBlockSegment($0)
                && time >= $0.startTime - 0.5
                && time < $0.endTime - 0.1
        }) else { return }
        handleSponsorBlockSegment(segment, enteredAt: time)
    }

    private func handleSponsorBlockSegment(
        _ segment: SponsorBlockSegment,
        enteredAt explicitEntryTime: TimeInterval? = nil
    ) {
        let currentTime = explicitEntryTime ?? player.currentTime().seconds
        // Preserve where the viewer actually entered the segment. A boundary observer can fire a
        // fraction late during ordinary playback, so positions near the beginning normalize to
        // the true segment start. A manual scrub into the middle retains its settled seek target.
        guard let undoPosition = sponsorBlockCoordinator.claimSkip(
            for: segment,
            enteredAt: currentTime,
            isEnabled: preferences.sponsorBlockEnabled,
            hasVideo: currentVideo != nil,
            behavior: preferences.sponsorBlockBehavior(for: segment.category),
            minimumSkipSeconds: preferences.sponsorBlockMinimumSkipSeconds
        ) else { return }
        sponsorBlockNoticeTask?.cancel()

        log.info("SponsorBlock skipping category=\(segment.category.rawValue, privacy: .public) duration=\(segment.endTime - segment.startTime, privacy: .public)s")
        seek(to: segment.endTime)
        sponsorBlockNotice = SponsorBlockNotice(
            category: segment.category,
            originalStartTime: undoPosition,
            kind: .skipped
        )
        scheduleSponsorBlockNoticeDismissal()
    }

    private func scheduleSponsorBlockNoticeDismissal() {
        let seconds = min(max(preferences.sponsorBlockNoticeSeconds, 1), 15)
        sponsorBlockNoticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.sponsorBlockNotice = nil
        }
    }

    /// Clears cached segment responses without changing the currently playing video's markers.
    func clearSponsorBlockCache() {
        sponsorBlockService.clearCache()
    }

    private func clearSponsorBlockState() {
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        sponsorBlockNoticeTask?.cancel()
        sponsorBlockNoticeTask = nil
        sponsorBlockNotice = nil
        sponsorBlockSegments = []
        sponsorBlockCoordinator.clear(on: player)
    }

    private func clearChapterState() {
        youtubeChapters = []
        communityChapters = []
        chapters = []
    }

    private func updateDisplayedChapters() {
        // Community chapters are a separate optional source. If none were submitted, retain
        // YouTube chapters; neither source is mixed with the other or used for automatic seeks.
        chapters = communityChapters.isEmpty ? youtubeChapters : communityChapters
    }

    /// Swap the player to a new item using the `AVQueuePlayer`-correct pattern. `replaceCurrentItem`
    /// is documented to be a no-op when the player's internal queue is empty (which is our usual
    /// state since the playable URL is short-lived and we never preload), so we always tear the
    /// queue down to nothing first and then insert. Also wires KVO so we hear about decode/auth
    /// failures the moment they happen (CoreMedia's `CFByteFlume err=-12939` style messages don't
    /// surface a structured `NSError` otherwise).
    private func loadItem(_ item: AVPlayerItem, originalAudioLanguageCode: String? = nil) {
        // Do not log the asset URL or path. Direct YouTube assets contain signed credentials in
        // both components; the candidate strategy is logged immediately before this method.
        let assetKind = item.asset is AVURLAsset ? "URL" : "composition"
        log.info("loadItem: removeAllItems + insert (assetKind=\(assetKind, privacy: .public))")
        player.removeAllItems()
        if let fastPlaybackLocalFileURL,
           (item.asset as? AVURLAsset)?.url != fastPlaybackLocalFileURL {
            self.fastPlaybackLocalFileURL = nil
            FastPlaybackLocalFileService.remove(fastPlaybackLocalFileURL)
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
        itemStatusObservation?.invalidate()
        itemPresentationSizeObservation?.invalidate()
        itemLoadedTimeRangesObservation?.invalidate()
        bufferedRanges = []
        liveSeekableRange = nil
        observedFrameRate = nil
        itemDiagnostics.reset()
        if let token = itemErrorLogObservation { NotificationCenter.default.removeObserver(token) }
        if let token = itemAccessLogObservation { NotificationCenter.default.removeObserver(token) }
        if let token = itemFailedToEndObservation { NotificationCenter.default.removeObserver(token) }
        itemFailedToEndObservation = nil

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
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
                       !self.isInstallingFastPlayback {
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

        itemPresentationSizeObservation = item.observe(\.presentationSize, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                let size = item.presentationSize
                guard self.player.currentItem === item,
                      size.width.isFinite, size.height.isFinite,
                      size.width > 0, size.height > 0 else { return }
                self.videoPresentationSize = size
            }
        }

        itemLoadedTimeRangesObservation = item.observe(\.loadedTimeRanges, options: [.new, .initial]) { [weak self] item, _ in
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

        itemErrorLogObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let entry = item?.errorLog()?.events.last else { return }
            // Never include `entry.uri`: YouTube playback URLs are signed, sensitive, and
            // short-lived. Resolver identity is enough to correlate this with candidate logs.
            self?.log.error("AVPlayerItem error-log: domain=\(entry.errorDomain, privacy: .public) code=\(entry.errorStatusCode, privacy: .public) comment=\(entry.errorComment ?? "", privacy: .public)")
        }

        itemFailedToEndObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item else { return }
                self.recoverAcceptedStreamIfNeeded(item, reason: "failed-to-play-to-end")
            }
        }

        itemAccessLogObservation = NotificationCenter.default.addObserver(
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
              !isInstallingFastPlayback else { return }
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

    private func playbackRecovery(
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

    private func resolveAndPlay(
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
            if candidate.strategy == .nativePaired {
                let preparationStartedAt = Date()
                log.info("resolveAndPlay: preparing paired candidate for \(video.id, privacy: .public) (limit=30s)")
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
                    log.info("resolveAndPlay: paired candidate prepared for \(video.id, privacy: .public) in \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s")
                case .failed(let detail):
                    log.notice("resolveAndPlay: paired candidate preparation failed for \(video.id, privacy: .public) after \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s \(detail, privacy: .public)")
                    excludedStrategies.insert(candidate.strategy)
                    continue
                case .timedOut:
                    log.notice("resolveAndPlay: paired candidate preparation timed out for \(video.id, privacy: .public) after \(Date().timeIntervalSince(preparationStartedAt), privacy: .public)s")
                    excludedStrategies.insert(candidate.strategy)
                    continue
                case .cancelled:
                    return
                }
            } else {
                do {
                    item = try await itemFactory.makeItem(for: candidate)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, playbackSessionID == sessionID, currentVideo?.id == video.id else { return }
                    log.notice("resolveAndPlay: candidate preparation failed strategy=\(candidate.strategy.rawValue, privacy: .public) error=\(PlayerItemReadinessGate.describe(itemError: error), privacy: .public)")
                    excludedStrategies.insert(candidate.strategy)
                    continue
                }
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
    private func applyQualityCap(to item: AVPlayerItem) {
        applyQualityCap(to: item, quality: playbackQuality)
    }

    /// Reapply the adaptive cap when Settings changes without replacing the current item.
    func refreshPlaybackQualityLimits() {
        guard let item = player.currentItem else { return }
        applyQualityCap(to: item)
    }

    private func applyQualityCap(to item: AVPlayerItem, quality: VideoQuality) {
        // `.zero` means unrestricted. Reset first so moving from a capped choice back to Auto
        // takes effect on the already-playing HLS asset.
        item.preferredMaximumResolution = .zero
        item.preferredMaximumResolutionForExpensiveNetworks = .zero
        guard quality != .audioOnly else { return }

        // AVPlayer applies these preferences only to HLS. Local and progressive files retain
        // their encoded quality; neither setting causes a source swap or playback interruption.
        let globalHeightCap = quality == .auto ? nil : quality.heightCap
        if let globalHeightCap, globalHeightCap > 0 {
            item.preferredMaximumResolution = CGSize(
                width: globalHeightCap * 16 / 9, height: globalHeightCap
            )
        }
        let cellularQuality = preferences.cellularPlaybackQuality
        if cellularQuality != .auto, let cellularHeightCap = cellularQuality.heightCap,
           cellularHeightCap > 0 {
            let heightCap = min(globalHeightCap ?? cellularHeightCap, cellularHeightCap)
            item.preferredMaximumResolutionForExpensiveNetworks = CGSize(
                width: heightCap * 16 / 9, height: heightCap
            )
        }
    }

    private func readinessTimeout(for strategy: PlaybackStrategy) -> Duration {
        switch strategy {
        case .b5iIOS, .b5iTVHTML5:
            return .seconds(4)
        case .localFile, .native, .nativePaired, .nativeProgressive:
            return .seconds(12)
        }
    }

    private func finishPlaybackSetup(video: Video, skipRecommendations: Bool) {
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
            recommendationTask = Task { [weak self] in
                await self?.fillQueueWithRecommendations(for: video)
            }
        }
    }

    /// Fetches `MoreVideoInfosResponse` for the current video and appends the recommended videos to
    /// the queue. This is what makes the player behave like the YouTube app: tap any video and a
    /// fresh "up next" queue is ready to advance when the current track ends.
    private func fillQueueWithRecommendations(for seed: Video) async {
        let targetUpcomingCount = min(max(preferences.upNextInitialCount, 3), 15)
        let upcomingCount = activePlaylist != nil
            ? min(targetUpcomingCount, playlistRecommendations.filter { !VideoBlocklist.shared.blocks($0) }.count)
            : min(targetUpcomingCount, queue.items.dropFirst(queue.currentIndex + 1)
                .filter { !VideoBlocklist.shared.blocks($0) }.count)
        guard upcomingCount < targetUpcomingCount else {
            log.debug("Recommendation refill skipped for \(seed.id, privacy: .public): \(upcomingCount, privacy: .public) upcoming items remain")
            return
        }

        do {
            let info = try await VideoContentPrefetchStore.shared.fetchDetails(videoID: seed.id)
            try Task.checkCancellation()
            guard currentVideo?.id == seed.id else {
                log.debug("Discarding stale recommendations for \(seed.id, privacy: .public)")
                return
            }
            installVideoDetails(info, for: seed.id)
            let existingIDs = Set(queue.items.map(\.id)).union(playlistRecommendations.map(\.id))
            let needed = targetUpcomingCount - upcomingCount
            let fresh = info.recommended.filter {
                !existingIDs.contains($0.id) && !VideoBlocklist.shared.blocks($0)
            }
            let toAppend = Array(fresh.prefix(needed))
            recommendationBacklog = Array(fresh.dropFirst(toAppend.count))
            recommendationContinuationToken = info.recommendedContinuationToken
            if activePlaylist != nil {
                playlistRecommendations = toAppend
            } else {
                queue.append(contentsOf: toAppend)
            }
            log.info("Queued \(toAppend.count, privacy: .public) recommendations for \(seed.id, privacy: .public)")
        } catch is CancellationError {
            log.debug("Recommendation fetch cancelled for \(seed.id, privacy: .public)")
        } catch {
            log.notice("Recommendation fetch failed for \(seed.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    var canLoadMoreRecommendations: Bool {
        !recommendationBacklog.isEmpty || recommendationContinuationToken != nil
    }

    /// Adds the next small recommendation page to Up Next. The remainder of YouTube's initial
    /// response is consumed before its network continuation, so no recommendations are skipped.
    func loadMoreRecommendations() async {
        guard !isLoadingMoreRecommendations, canLoadMoreRecommendations else { return }
        isLoadingMoreRecommendations = true
        defer { isLoadingMoreRecommendations = false }

        recommendationBacklog.removeAll { VideoBlocklist.shared.blocks($0) }

        if !recommendationBacklog.isEmpty {
            let page = Array(recommendationBacklog.prefix(5))
            recommendationBacklog.removeFirst(page.count)
            if activePlaylist != nil {
                playlistRecommendations.append(contentsOf: page)
            } else {
                queue.append(contentsOf: page)
            }
            return
        }

        guard let token = recommendationContinuationToken else { return }
        let videoID = currentVideo?.id
        do {
            let page = try await videoService.fetchRecommendedVideos(continuation: token)
            guard !Task.isCancelled, currentVideo?.id == videoID else { return }
            let existingIDs = Set(queue.items.map(\.id)).union(playlistRecommendations.map(\.id))
            let fresh = page.videos.filter {
                !existingIDs.contains($0.id) && !VideoBlocklist.shared.blocks($0)
            }
            let visible = Array(fresh.prefix(5))
            recommendationBacklog = Array(fresh.dropFirst(visible.count))
            recommendationContinuationToken = page.continuationToken
            if activePlaylist != nil {
                playlistRecommendations.append(contentsOf: visible)
            } else {
                queue.append(contentsOf: visible)
            }
        } catch {
            log.notice("Recommendation continuation failed: \(String(describing: error), privacy: .public)")
        }
    }

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

    private func installObservers() {
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
        // Periodic time observation via Combine-friendly bridging.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                if let pendingSeekTarget = self.pendingSeekTarget {
                    self.elapsed = pendingSeekTarget
                } else {
                    self.elapsed = time.seconds.isFinite ? time.seconds : 0
                }
                if let item = self.player.currentItem {
                    if self.isPlaying,
                       let fps = item.tracks.map(\.currentVideoFrameRate).first(where: {
                           $0.isFinite && $0 >= 10 && $0 <= 240
                       }) {
                        self.observedFrameRate = (item, Double(fps))
                    }
                    let total = item.duration.seconds
                    if total.isFinite { self.duration = total }
                    self.updateLiveSeekableRange(for: item)
                    if self.currentVideo?.isLive == true,
                       self.loadState == .readyToPlay,
                       item.status == .readyToPlay {
                        self.itemDiagnostics.logLiveDVRIfNeeded(
                            for: item,
                            videoID: self.currentVideo?.id ?? "unknown"
                        )
                    }
                }
                self.accumulateHistoryPlaybackTime()
                self.persistCurrentPlaybackProgress(force: false)
                self.updateNowPlaying()
            }
        }

        // Handle the retained item at natural end. `actionAtItemEnd = .pause` prevents
        // AVQueuePlayer from removing it before replay/backward-seek can reuse it.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard let endedItem = notification.object as? AVPlayerItem,
                      endedItem === self.player.currentItem else { return }
                self.log.info("Playback reached item end: sourceDuration=\(endedItem.duration.seconds, privacy: .public)s metadataDuration=\(self.currentVideo?.duration ?? -1, privacy: .public)s")
                self.isPlaying = false
                self.wantsPlayback = false
                self.hasEnded = true
                self.elapsed = self.duration
                self.persistCurrentPlaybackProgress(force: true)
                self.updateNowPlaying()

                // Stop-before-autoplay is essential: pausing alone would still let the ordinary
                // end observer advance to the next recommendation or repeat the current item.
                if self.sleepTimerOption == .endOfVideo {
                    self.setSleepTimer(.off)
                    return
                }

                // Loop-one is an explicit playback instruction and therefore remains active even
                // when general autoplay is disabled. Any successful transition resets `hasEnded`
                // in `load`; if there is no next item, the replay state stays visible.
                if self.queue.repeatMode == .one || self.preferences.autoplayNext {
                    self.playNext()
                }
            }
        }

        // Mirror AVPlayer's transport state into our `isPlaying` flag so the custom transport row
        // under the video title (and the popup-bar play/pause glyph) reflects taps on the native
        // AVPlayerViewController controls. Without this, hitting the native pause button on the
        // video surface left our SwiftUI button showing "Pause" forever.
        // The current video's menu rate is separate from the saved default. The
        // capability-limited AVPlayer rate and temporary holds must not change either choice.

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                // Read the status inside the hop rather than capturing it at KVO time. Optimistic
                // play installs and tears down items in quick succession, so a captured value can
                // land after a later transition and leave `isPlaying` (and therefore the Now
                // Playing rate) describing a candidate we already rejected.
                switch self.player.timeControlStatus {
                case .playing:
                    if !self.isPlaying {
                        self.log.info("KVO timeControlStatus → playing (sync isPlaying=true)")
                        self.isPlaying = true
                    }
                case .paused:
                    if self.isPlaying {
                        self.log.info("KVO timeControlStatus → paused (sync isPlaying=false)")
                        self.isPlaying = false
                    }
                case .waitingToPlayAtSpecifiedRate:
                    // Buffering / stalled. Treat as "playing" so the UI still shows pause icon,
                    // matching what the native AVPlayerViewController shows.
                    if !self.isPlaying {
                        self.isPlaying = true
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func updateNowPlaying() {
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

    // MARK: - Resume position

    /// Resumes only meaningful, unfinished progress. A short opening is treated as unwatched, and
    /// the final 30 seconds are treated as completed so finished videos restart normally.
    private func applyStoredResumePosition(
        _ progress: (position: TimeInterval, duration: TimeInterval)?,
        for video: Video
    ) {
        guard let position = storedResumePosition(progress, for: video) else { return }
        log.info("Resuming \(video.id, privacy: .public) at \(position, privacy: .public)s")
        seek(to: position)
    }

    private func storedResumePosition(
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
    private func persistCurrentPlaybackProgress(force: Bool) {
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

    private func accumulateHistoryPlaybackTime() {
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

    private func persistManualQueue() {
        PlayerManualQueueStore.persist(manualQueue)
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

        if let url = video.thumbnailURL,
           let cached = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey) {
            currentArtwork = cached
            updateNowPlaying()
            return
        }

        // Xattr fallback for downloaded-only videos. `DownloadsStore.thumbnail(forVideoID:)`
        // is synchronous (the entries snapshot lives in memory) so we can decode + assign
        // inline rather than through a Task / background actor.
        let videoID = video.id
        if let data = DownloadsStore.shared.thumbnail(forVideoID: videoID),
           let image = UIImage(data: data) {
            currentArtwork = image
            updateNowPlaying()
        }

        // Async network/disk fetch as last resort.
        guard let url = video.thumbnailURL else { return }
        KingfisherManager.shared.retrieveImage(with: url) { [weak self, videoID = video.id] result in
            guard case .success(let value) = result else { return }
            Task { @MainActor in
                guard let self else { return }
                // Drop the result if the user switched videos while the fetch was inflight.
                guard self.currentVideo?.id == videoID else { return }
                self.currentArtwork = value.image
                self.updateNowPlaying()
            }
        }
    }
}
