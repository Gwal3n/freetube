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
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var miniPlayerVisible: Bool = false
    var fullScreenPresented: Bool = false

    // MARK: - AVPlayer

    /// `AVQueuePlayer` to unlock `advanceToNextItem()` and queue introspection for future preload.
    /// IMPORTANT: don't use `replaceCurrentItem(with:)` to load tracks — it's a no-op on
    /// `AVQueuePlayer` when the internal queue is empty (which is our usual state). Use the
    /// `removeAllItems()` + `insert(_:after:)` pattern via `swap(to:)` below.
    let player = AVQueuePlayer()

    // MARK: - Collaborators

    let queue: QueueManager
    private let resolver: any PlaybackResolving
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

    private var timeObserver: Any?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var statusCancellable: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemLoadStartedAt: Date?
    /// KVO-driven readiness handshake for the candidate currently under test.
    ///
    /// `waitForReadiness(of:timeout:)` parks a continuation here and the single `\.status`
    /// observation installed by `observe(item:)` resumes it. Deliberately one observer per item
    /// and one waiter at a time: a second competing observer would double-resume. `readinessToken`
    /// is bumped for every wait so a late timeout or cancellation waker can only ever settle the
    /// wait it was created for, never a newer candidate's. All three are `@MainActor`-isolated,
    /// which is what makes "resumed exactly once" checkable by reading this file.
    private var readinessContinuation: CheckedContinuation<ItemReadiness, Never>?
    private var readinessItem: AVPlayerItem?
    private var readinessToken = 0
    private var itemErrorLogObservation: NSObjectProtocol?
    private var playerErrorObservation: NSKeyValueObservation?
    private var defaultRateObservation: NSKeyValueObservation?
    init(
        queue: QueueManager = QueueManager(),
        resolver: any PlaybackResolving = PlaybackResolver(),
        preferences: UserPreferences = UserPreferences()
    ) {
        self.queue = queue
        self.resolver = resolver
        self.preferences = preferences
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
        // Restore the last-used playback speed. `defaultRate` is what `AVPlayerViewController`'s
        // speed menu writes, and `AVPlayer.play()` resumes at this rate (not the transient `rate`).
        // Setting it *before* installObservers keeps the KVO from firing back and re-saving the
        // same value during launch.
        player.defaultRate = Float(preferences.playbackRate)
        installObservers()
    }

    /// Tear-down hook for tests / app lifecycle. Call before releasing the manager. We avoid `deinit`
    /// here so we don't have to reach into main-actor-isolated state from a nonisolated context.
    func tearDownObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
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
    /// render), `miniPlayerVisible` flipped true so LNPopupUI shows the bar, NowPlayingCenter
    /// update for lock-screen artwork, and the standard observe/loadItem flow so errors and
    /// playback state still surface through the existing UI.
    func loadLocalFile(at fileURL: URL, title: String, source: String?, thumbnailURL: URL?) {
        log.info("loadLocalFile path=\(fileURL.path, privacy: .public) title=\"\(title, privacy: .public)\"")
        // A YouTube resolution still in flight would otherwise keep testing candidates against a
        // player we're about to hand a local file, and its readiness wait would sit out its full
        // timeout. Cancelling settles that wait immediately.
        resolutionTask?.cancel()
        recommendationTask?.cancel()
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
        miniPlayerVisible = true
        fullScreenPresented = true
        elapsed = 0
        duration = 0
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
    func load(
        _ video: Video,
        autoplay: Bool = true,
        skipRecommendations: Bool = false,
        expandPlayer: Bool = true
    ) {
        log.info("load(\(video.id, privacy: .public)) autoplay=\(autoplay, privacy: .public) skipRecs=\(skipRecommendations, privacy: .public)")
        resolutionTask?.cancel()
        recommendationTask?.cancel()
        queueAcceptsRecommendations = !skipRecommendations
        // Pause and tear down anything currently playing. Otherwise we'd keep streaming audio from
        // the previous video while the new one's file is downloading — which is what the user kept
        // hearing when they tapped "next" mid-download.
        if isPlaying {
            log.info("load: pausing current playback before resolving new video")
            pause()
        }
        if !player.items().isEmpty {
            log.debug("load: clearing AVQueuePlayer items (\(self.player.items().count, privacy: .public) entries)")
            player.removeAllItems()
        }
        currentVideo = video
        // Ordinary playback gets a fresh, bounded recommendation set for each video and retains no
        // history. Explicit playlist batches keep their curated order and skip recommendations.
        if skipRecommendations {
            queue.setCurrent(video)
        } else {
            queue.replace(with: [video])
        }
        miniPlayerVisible = true
        if expandPlayer {
            fullScreenPresented = true
        }
        loadState = .resolving
        // Wipe transport state from the previous video so a stray time-observer tick during the
        // transition (the periodic callback can fire AFTER currentVideo flips but BEFORE the new
        // AVPlayerItem is installed) doesn't carry the old item's elapsed/duration into a save —
        // that's what showed phantom progress bars on cells the user never played.
        elapsed = 0
        duration = 0
        recordWatchHistory(video: video)
        refreshArtwork(for: video)
        resolutionTask = Task { [weak self] in
            await self?.resolveAndPlay(video: video, autoplay: autoplay, skipRecommendations: skipRecommendations)
        }
    }

    private var resolutionTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?

    /// Upserts a `WatchHistoryEntry` so the Library's "Recents" section reflects what the user
    /// played. Same-id taps just bump `watchedAt` so the row floats to the top. The actor hop keeps
    /// the SQL write off the main thread; @Query observers see the change automatically once the
    /// background context saves.
    private func recordWatchHistory(video: Video) {
        let videoID = video.id
        let title = video.title
        let channelName = video.channelName
        let thumbnailURL = video.thumbnailURL
        Task {
            await PersistenceWriter.shared.upsertWatchHistory(
                videoID: videoID,
                title: title,
                channelName: channelName,
                thumbnailURL: thumbnailURL
            )
        }
    }

    func play() {
        log.info("play()")
        player.play()
        isPlaying = true
    }

    func pause() {
        log.info("pause()")
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        log.info("togglePlayPause() (isPlaying=\(self.isPlaying, privacy: .public))")
        isPlaying ? pause() : play()
    }

    func seek(to seconds: TimeInterval) {
        log.info("seek(to: \(seconds, privacy: .public)s)")
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekRelative(by delta: TimeInterval) {
        log.info("seekRelative(by: \(delta, privacy: .public)s)")
        seek(to: max(0, min(elapsed + delta, duration)))
    }

    func playNext() {
        log.info("playNext() — queue size=\(self.queue.items.count, privacy: .public) currentIndex=\(self.queue.currentIndex, privacy: .public)")
        if let next = queue.advance() {
            load(next, expandPlayer: false)
            return
        }
        // Queue at end. If this queue accepts recommendations and the user hasn't asked for
        // repeat-all/repeat-one, refill from the last item's recommendations and try advancing
        // again — that's the "endless queue" behavior: every time we hit the bottom, more recs
        // refill behind us.
        guard queueAcceptsRecommendations,
              queue.repeatMode == .off,
              let seed = queue.items.last else {
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
            if let next = self.queue.advance() {
                self.load(next, expandPlayer: false)
            }
        }
    }

    func playPrevious() {
        log.info("playPrevious() — queue size=\(self.queue.items.count, privacy: .public) currentIndex=\(self.queue.currentIndex, privacy: .public)")
        guard let previous = queue.previous() else {
            log.notice("playPrevious: at start of queue, nothing to go back to")
            return
        }
        load(previous, expandPlayer: false)
    }

    func dismiss() {
        log.info("dismiss()")
        resolutionTask?.cancel()
        resolutionTask = nil
        recommendationTask?.cancel()
        recommendationTask = nil
        pause()
        miniPlayerVisible = false
        fullScreenPresented = false
        currentVideo = nil
        loadState = .idle
        player.removeAllItems()
        NowPlayingCenter.clear()
    }

    // MARK: - Internals

    /// Swap the player to a new item using the `AVQueuePlayer`-correct pattern. `replaceCurrentItem`
    /// is documented to be a no-op when the player's internal queue is empty (which is our usual
    /// state since the playable URL is short-lived and we never preload), so we always tear the
    /// queue down to nothing first and then insert. Also wires KVO so we hear about decode/auth
    /// failures the moment they happen (CoreMedia's `CFByteFlume err=-12939` style messages don't
    /// surface a structured `NSError` otherwise).
    private func loadItem(_ item: AVPlayerItem) {
        // Do not log the asset URL or path. Direct YouTube assets contain signed credentials in
        // both components; the candidate strategy is logged immediately before this method.
        let assetKind = item.asset is AVURLAsset ? "URL" : "composition"
        log.info("loadItem: removeAllItems + insert (assetKind=\(assetKind, privacy: .public))")
        player.removeAllItems()
        player.insert(item, after: nil)
        log.debug("loadItem: queue size after insert=\(self.player.items().count, privacy: .public)")
        observe(item: item)
    }

    private func observe(item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        if let token = itemErrorLogObservation { NotificationCenter.default.removeObserver(token) }

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                switch item.status {
                case .unknown:
                    self.log.info("AVPlayerItem status: unknown")
                case .readyToPlay:
                    let preparationTime = self.itemLoadStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    self.log.info("AVPlayerItem status: readyToPlay after \(preparationTime, privacy: .public)s (duration=\(item.duration.seconds, privacy: .public)s)")
                    self.itemLoadStartedAt = nil
                    self.finishReadiness(.ready, for: item)
                case .failed:
                    let err = item.error as NSError?
                    self.log.error("AVPlayerItem status: FAILED domain=\(err?.domain ?? "?", privacy: .public) code=\(err?.code ?? 0, privacy: .public) info=\(String(describing: err?.userInfo), privacy: .public)")
                    self.finishReadiness(.failed(Self.describe(itemError: item.error)), for: item)
                @unknown default:
                    break
                }
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
    }

    private func resolveAndPlay(video: Video, autoplay: Bool, skipRecommendations: Bool = false) async {
        log.info("resolveAndPlay: start for \(video.id, privacy: .public)")
        let resolutionStartedAt = Date()
        loadState = .resolving
        var excludedStrategies = Set<PlaybackStrategy>()

        while !Task.isCancelled, currentVideo?.id == video.id {
            let candidate: PlaybackCandidate
            do {
                candidate = try await resolver.resolve(
                    video: video,
                    quality: preferences.preferredQuality,
                    excluding: excludedStrategies
                )
            } catch is CancellationError {
                log.debug("resolveAndPlay: cancelled for \(video.id, privacy: .public)")
                return
            } catch {
                guard currentVideo?.id == video.id else { return }
                log.error("resolveAndPlay: all resolvers failed for \(video.id, privacy: .public): \(String(describing: error), privacy: .public)")
                loadState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }

            guard !Task.isCancelled, currentVideo?.id == video.id else {
                log.debug("resolveAndPlay: discarded stale result for \(video.id, privacy: .public)")
                return
            }

            log.info("resolveAndPlay: testing candidate=\(candidate.strategy.rawValue, privacy: .public) after \(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
            let item = AVPlayerItem(url: candidate.source.url)
            applyQualityCap(to: item)
            itemLoadStartedAt = Date()
            loadItem(item)
            // Optimistic start. AVPlayer has no "first frame rendered" signal — only
            // `.readyToPlay`, which on a warm resolve accounted for ~80% of the tap-to-video
            // wait. So we stop gating the transport on it: the candidate is still validated
            // below and still rejected on failure/timeout, but the player is already holding a
            // play request when readiness lands, so it starts without waiting for us to notice.
            // This only works because `automaticallyWaitsToMinimizeStalling` is `true` — see the
            // note in `init`, where turning it off silently discards this call.
            // `.buffering` keeps the UI on the video's thumbnail instead of a spinner.
            loadState = .buffering
            updateNowPlaying()
            if autoplay {
                log.info("resolveAndPlay: optimistic play issued for candidate=\(candidate.strategy.rawValue, privacy: .public) at \(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
                play()
            }

            let readiness = await waitForReadiness(
                of: item,
                timeout: readinessTimeout(for: candidate.strategy)
            )
            guard !Task.isCancelled, currentVideo?.id == video.id else {
                log.debug("resolveAndPlay: discarded candidate result for stale video \(video.id, privacy: .public)")
                return
            }

            switch readiness {
            case .ready:
                // `total` still measures resolve → `.readyToPlay`, unchanged, so the number stays
                // comparable with builds that played only after this point.
                log.info("resolveAndPlay: accepted candidate=\(candidate.strategy.rawValue, privacy: .public) total=\(Date().timeIntervalSince(resolutionStartedAt), privacy: .public)s")
                loadState = .readyToPlay
                updateNowPlaying()
                // Usually redundant — the optimistic `play()` above has either started the item or
                // parked the player in `.waitingToPlayAtSpecifiedRate`, and this covers the case
                // where a rejected candidate left the transport paused.
                //
                // Ask the player, not `isPlaying`. That flag is a prediction written by `play()`
                // for immediate UI feedback, so after an optimistic start it reads `true` whether
                // or not AVPlayer honoured the request. Gating this on it means the one situation
                // that needs a retry is the one situation where the retry is skipped.
                if autoplay, player.timeControlStatus == .paused { play() }
                finishPlaybackSetup(video: video, skipRecommendations: skipRecommendations)
                return
            case .failed(let description):
                log.notice("resolveAndPlay: rejected candidate=\(candidate.strategy.rawValue, privacy: .public) reason=failed detail=\(description, privacy: .public)")
            case .timedOut:
                log.notice("resolveAndPlay: rejected candidate=\(candidate.strategy.rawValue, privacy: .public) reason=readiness-timeout")
            }

            excludedStrategies.insert(candidate.strategy)
            // The optimistic `play()` left the transport running (rate 1, possibly stalled) on a
            // stream we're now abandoning. Stop it *before* tearing the queue down so `isPlaying`
            // and the Now Playing rate don't advertise playback for a rejected candidate while the
            // next one resolves.
            if isPlaying { pause() }
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
        let quality = preferences.preferredQuality
        guard quality != .auto, let heightCap = quality.heightCap, heightCap > 0 else { return }
        // AVPlayer treats this as an upper bound on a variant's frame size, not an exact match,
        // so deriving the width from 16:9 is safe for taller and wider aspect ratios alike.
        item.preferredMaximumResolution = CGSize(width: heightCap * 16 / 9, height: heightCap)
    }

    private enum ItemReadiness {
        case ready
        case failed(String)
        case timedOut
    }

    /// Waits for `item` to reach `.readyToPlay` (accept) or `.failed` (reject), giving up after
    /// `timeout`.
    ///
    /// KVO rather than the 100ms poll this replaced: at ~2s of buffering the poll cost up to half a
    /// frame of latency on the accept path for no benefit, and it woke the main actor twenty times
    /// per candidate. The `\.status` observation installed by `observe(item:)` is the *only* status
    /// observer — it calls `finishReadiness(_:for:)`, which resumes the continuation parked here.
    ///
    /// Exactly-once resume: every resume path goes through `finishReadiness(_:token:)` on the main
    /// actor, which nils the continuation before resuming. The three racers are KVO, the timeout
    /// task, and task cancellation (`load()` cancelling `resolutionTask` on a rapid video switch);
    /// whichever arrives first wins and the rest no-op.
    private func waitForReadiness(of item: AVPlayerItem, timeout: Duration) async -> ItemReadiness {
        // Defensive: settle any wait that outlived its caller before adopting a new item, so the
        // "one parked continuation" invariant can't be broken by an unexpected call order.
        finishReadiness(.failed("superseded"), token: readinessToken)

        // `observe(item:)` runs before we get here, so a status that already settled produced a
        // KVO callback we can no longer catch. Read it directly instead of waiting for an edge
        // that will never come — this is also the fast path for local files.
        switch item.status {
        case .readyToPlay:
            return .ready
        case .failed:
            return .failed(Self.describe(itemError: item.error))
        case .unknown:
            break
        @unknown default:
            break
        }

        if Task.isCancelled { return .failed("cancelled") }

        readinessToken += 1
        let token = readinessToken
        readinessItem = item

        // Inherits main-actor isolation from this method, so `finishReadiness` is a direct call.
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return // Cancelled because the wait already settled.
            }
            self?.finishReadiness(.timedOut, token: token)
        }
        defer { timeoutTask.cancel() }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.readinessContinuation = continuation
                // The KVO handler hops through a `Task` before it reaches `finishReadiness`, so a
                // status change can land in the gap between installing the item and parking this
                // continuation — where it would find nothing to resume and we'd sit out the whole
                // timeout on an item that is already playable. Re-reading the status here closes
                // that window; resuming from inside the body is legal.
                switch item.status {
                case .readyToPlay:
                    self.finishReadiness(.ready, for: item)
                case .failed:
                    self.finishReadiness(.failed(Self.describe(itemError: item.error)), for: item)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        } onCancel: {
            // `onCancel` is nonisolated, hence the explicit hop. Only the token travels — an
            // `AVPlayerItem` isn't `Sendable`.
            Task { @MainActor [weak self] in
                self?.finishReadiness(.failed("cancelled"), token: token)
            }
        }
    }

    /// Resumes the parked readiness continuation if it belongs to `item`. Called from the `\.status`
    /// KVO handler, which fires for whichever item is currently observed — that may be a newer item
    /// than the one being waited on, hence the identity check.
    private func finishReadiness(_ outcome: ItemReadiness, for item: AVPlayerItem) {
        guard readinessItem === item else { return }
        finishReadiness(outcome, token: readinessToken)
    }

    /// Single resume funnel. Nils the continuation before resuming so a re-entrant caller can't
    /// resume it twice.
    private func finishReadiness(_ outcome: ItemReadiness, token: Int) {
        guard token == readinessToken, let continuation = readinessContinuation else { return }
        readinessContinuation = nil
        readinessItem = nil
        continuation.resume(returning: outcome)
    }

    /// Compact, log-safe rendering of an `AVPlayerItem.error`. Domain + code only: the userInfo of
    /// a playback failure can carry the signed asset URL.
    private static func describe(itemError: Error?) -> String {
        let error = itemError as NSError?
        return "domain=\(error?.domain ?? "?") code=\(error?.code ?? 0)"
    }

    private func readinessTimeout(for strategy: PlaybackStrategy) -> Duration {
        switch strategy {
        case .b5iIOS, .b5iTVHTML5:
            return .seconds(4)
        case .localFile, .native, .legacyDownload:
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
        if !skipRecommendations {
            recommendationTask = Task { [weak self] in
                await self?.fillQueueWithRecommendations(for: video)
            }
        }
    }

    /// Fetches `MoreVideoInfosResponse` for the current video and appends the recommended videos to
    /// the queue. This is what makes the player behave like the YouTube app: tap any video and a
    /// fresh "up next" queue is ready to advance when the current track ends.
    private func fillQueueWithRecommendations(for seed: Video) async {
        let targetUpcomingCount = 5
        let upcomingCount = queue.availableUpcomingCount(limit: targetUpcomingCount)
        guard upcomingCount < targetUpcomingCount else {
            log.debug("Recommendation refill skipped for \(seed.id, privacy: .public): \(upcomingCount, privacy: .public) upcoming items remain")
            return
        }

        do {
            let info = try await VideoService().fetchMoreInfo(id: seed.id)
            try Task.checkCancellation()
            guard currentVideo?.id == seed.id else {
                log.debug("Discarding stale recommendations for \(seed.id, privacy: .public)")
                return
            }
            let existingIDs = Set(queue.items.map(\.id))
            let needed = targetUpcomingCount - upcomingCount
            let toAppend = Array(
                info.recommended
                    .filter { !existingIDs.contains($0.id) }
                    .prefix(needed)
            )
            queue.append(contentsOf: toAppend)
            log.info("Queued \(toAppend.count, privacy: .public) recommendations for \(seed.id, privacy: .public)")
        } catch is CancellationError {
            log.debug("Recommendation fetch cancelled for \(seed.id, privacy: .public)")
        } catch {
            log.notice("Recommendation fetch failed for \(seed.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func installObservers() {
        // Periodic time observation via Combine-friendly bridging.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.elapsed = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem {
                    let total = item.duration.seconds
                    if total.isFinite { self.duration = total }
                }
                self.updateNowPlaying()
            }
        }

        // Auto-advance on item end.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.preferences.autoplayNext { self.playNext() }
            }
        }

        // Mirror AVPlayer's transport state into our `isPlaying` flag so the custom transport row
        // under the video title (and the popup-bar play/pause glyph) reflects taps on the native
        // AVPlayerViewController controls. Without this, hitting the native pause button on the
        // video surface left our SwiftUI button showing "Pause" forever.
        // Persist user-driven speed changes from AVPlayerViewController's built-in speed menu.
        // The menu writes to `defaultRate`; KVO catches the write and we save it to prefs so the
        // next app launch starts at the same speed.
        defaultRateObservation = player.observe(\.defaultRate, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            guard let newValue = change.newValue else { return }
            let rate = Double(newValue)
            // Sanity: defaultRate of 0 would mean "paused on play()" which YouTube/AVPlayerViewController
            // never offers as a user option. Ignore any such bogus write.
            guard rate > 0 else { return }
            Task { @MainActor in
                if abs(rate - self.preferences.playbackRate) > 0.001 {
                    self.log.info("playbackRate changed → \(rate, privacy: .public) (persisting)")
                    self.preferences.playbackRate = rate
                }
            }
        }

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
            rate: isPlaying ? 1.0 : 0.0,
            artwork: currentArtwork
        )
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
