import SwiftUI
import UIKit

/// Expanded player content hosted by the app's SwiftUI player container. This view renders the
/// surface, transport controls, metadata, and independently collapsible sections below.
@available(iOS 17.0, *)
struct FullScreenPlayer: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detailsModel = PlayerDetailsModel()
    @State private var controlsVisibility = PlayerControlsVisibilityModel()
    @State private var actionsModel = PlayerActionsModel()
    /// File URL the user wants to hand off to another app via the system "Open in…" share sheet.
    /// Non-nil → present the activity controller; tapped row sets this, sheet dismissal clears it.
    @State private var shareFileURL: URL?
    @State private var saveToPlaylistVideo: Video?
    @State private var gestureSeekPreview: TimeInterval?
    @State private var scrubberSeekPreview: TimeInterval?
    @State private var panelScrollOffset: CGFloat = 0
    @State private var panelScrollGestureActive = false
    /// Portrait videos use an in-place fullscreen mode rather than rotating a tall source into a
    /// short landscape viewport. The same fullscreen control toggles this state back off.
    @State private var portraitVideoFullscreen = false
    @AppStorage("autoplayNext") private var autoplayNext = true
    @AppStorage("prefetchVideoDetails") private var prefetchVideoDetails = true
    @AppStorage("showComments") private var showComments = true
    @AppStorage("showUpNext") private var showUpNext = true
    @AppStorage("upNextInitialCount") private var upNextInitialCount = 5
    @AppStorage("oledPlayerBackground") private var oledPlayerBackground = false
    @AppStorage("playerTopControlOrder") private var playerTopControlOrderRaw = PlayerTopControl.encodeOrder(PlayerTopControl.defaultOrder)
    @AppStorage("hiddenPlayerTopControls") private var hiddenPlayerTopControlsRaw = ""

    var body: some View {
        // Single dark-blur material under EVERYTHING — status bar inset, video chrome, transport,
        // comments, queue. Removing per-section backgrounds and using one full-screen material lets
        // the popup read as one continuous translucent surface instead of three stacked tones.
        //
        // The outer GeometryReader provides a stable viewport for both the display-correct
        // expanded ratio and the compact baseline (16:9 for ordinary/tall media, native ratio for
        // wide media). Their difference becomes the first part of the lower panel's scroll range,
        // allowing a tall player to behave as a collapsible header.
        GeometryReader { proxy in
            let isLandscape = verticalSizeClass == .compact
            let usesPortraitFullscreen = portraitVideoFullscreen && isPortraitVideo && !isLandscape
            let chapterPanelWidth: CGFloat = isLandscape && player.chapterListPresented
                ? min(360, proxy.size.width * 0.38)
                : 0
            let surfaceWidth = proxy.size.width - chapterPanelWidth
            // Landscape controls occupy the available viewport instead of insisting on a 16:9
            // frame taller than a modern phone's safe height. AVPlayer aspect-fits the video in
            // that region, preventing the timeline and bottom edge from being cropped.
            let compactSurfaceHeight = isLandscape
                ? proxy.size.height
                : PlayerViewportLayout.compactSurfaceHeight(
                    width: surfaceWidth,
                    presentationSize: player.videoPresentationSize
                )
            let expandedSurfaceHeight = usesPortraitFullscreen || isLandscape
                ? compactSurfaceHeight
                : PlayerViewportLayout.expandedSurfaceHeight(
                    width: surfaceWidth,
                    viewportHeight: proxy.size.height,
                    isLandscape: isLandscape,
                    presentationSize: player.videoPresentationSize
                )
            let collapseRange = usesPortraitFullscreen
                ? 0
                : max(0, expandedSurfaceHeight - compactSurfaceHeight)
            let consumedCollapse = min(max(panelScrollOffset, 0), collapseRange)
            let surfaceHeight = expandedSurfaceHeight - consumedCollapse
            let controlFrame = PlayerViewportLayout.controlFrame(
                surfaceSize: CGSize(width: surfaceWidth, height: surfaceHeight),
                isLandscape: isLandscape,
                hasChapterSidebar: chapterPanelWidth > 0,
                presentationSize: player.videoPresentationSize,
                safeAreaInsets: PlayerLayoutMetrics.safeAreaInsets
            )
            ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Pinning the ZStack to width × width*9/16 keeps the surface a stable height
                // across .resolving → .downloading → .readyToPlay (the underlying
                // AVPlayerViewController has zero intrinsic size while loading; the explicit
                // frame here is what stops the layout from jumping when the user taps a queue
                // item).
                // Layer order is load-bearing. `AVPlayerViewController` paints an opaque black
                // background, so the thumbnail has to sit *above* `PlayerSurface` to be visible at
                // all — it hides itself once `loadState` reaches `.readyToPlay`. The artwork view
                // owns that crossfade so load-state changes cannot animate player geometry.
                ZStack {
                    Color.black
                    PlayerSurface(
                        player: player.player,
                        pipDismissalRequest: player.pipDismissalRequest,
                        onSeekRelative: { seconds in
                            player.seekRelative(by: seconds)
                        },
                        onSeekAbsolute: { seconds in
                            player.seek(to: seconds)
                        },
                        onSeekPreview: { seconds in
                            gestureSeekPreview = seconds
                        },
                        onTogglePlayback: {
                            player.togglePlayPause()
                        },
                        onToggleControls: { togglePlayerControls() },
                        onRestoreFromPictureInPicture: {
                            player.miniPlayerVisible = true
                            player.fullScreenPresented = true
                            player.requestInlinePlaybackRestoration()
                        }
                    )
                    PlayerArtworkBackdrop(artwork: player.currentArtwork, state: player.loadState)
                    DownloadProgressOverlay(state: player.loadState)
                    Color.black
                        .opacity(controlsVisibility.isVisible ? 0.28 : 0)
                        // Dim the stable player surface rather than AVPlayer's presentation rect.
                        // The latter changes from unknown/full-size to the decoded aspect ratio
                        // as a new item becomes ready, which made non-16:9 videos flash unevenly.
                        // Letterbox pixels are already black, so covering them has no visible cost.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    PlayerTransportOverlay(
                        isVisible: controlsVisibility.isVisible,
                        isSeekPreviewActive: gestureSeekPreview != nil || scrubberSeekPreview != nil,
                        previewElapsed: scrubberSeekPreview ?? gestureSeekPreview,
                        hasPrevious: hasPrevious,
                        hasNext: hasNext,
                        videoTitle: player.currentVideo?.title ?? "",
                        channelName: player.currentVideo?.channelName ?? "",
                        usesLandscapeLayout: isLandscape,
                        showsCollapseButton: !isLandscape && !usesPortraitFullscreen,
                        additionalTopControls: AnyView(
                            PlayerTopControls(
                                controls: visiblePlayerTopControls,
                                playbackRate: player.playbackRate,
                                isMuted: player.isMuted,
                                isLooping: player.isLoopingCurrentVideo,
                                isAutoplayEnabled: autoplayNext,
                                isFullscreen: isLandscape || portraitFullscreenActive,
                                onSetPlaybackRate: { rate in
                                    player.setPlaybackRate(rate)
                                    showPlayerControls()
                                },
                                onToggleLoop: {
                                    player.toggleLoopCurrentVideo()
                                    showPlayerControls()
                                },
                                onToggleMute: {
                                    player.toggleMute()
                                    showPlayerControls()
                                },
                                onToggleFullscreen: toggleFullscreen,
                                onToggleAutoplay: {
                                    autoplayNext.toggle()
                                    showPlayerControls()
                                }
                            )
                        ),
                        bottomTimelinePadding: PlayerViewportLayout.timelineBottomPadding(
                            availableSize: controlFrame.size,
                            isLandscape: isLandscape
                        ),
                        onTogglePlayPause: {
                            player.togglePlayPause()
                            showPlayerControls()
                        },
                        onSeek: {
                            player.seek(to: $0)
                            showPlayerControls()
                        },
                        onSeekPreviewChanged: { seconds in
                            scrubberSeekPreview = seconds
                        },
                        onShowChapters: {
                            guard !player.chapters.isEmpty else { return }
                            withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                                player.chapterListPresented.toggle()
                            }
                            showPlayerControls()
                        },
                        onPrevious: {
                            player.playPrevious()
                            showPlayerControls()
                        },
                        onNext: {
                            player.playNext()
                            showPlayerControls()
                        },
                        onCollapse: {
                            @Bindable var p = player
                            p.chapterListPresented = false
                            p.fullScreenPresented = false
                        }
                    )
                    .frame(width: controlFrame.width, height: controlFrame.height)
                    .position(x: controlFrame.midX, y: controlFrame.midY)
                    if let previewTime = scrubberSeekPreview,
                       let tile = player.storyboard?.tile(
                           at: previewTime,
                           duration: player.duration,
                           maximumWidth: 320,
                           maximumHeight: 180
                       ) {
                        StoryboardPreview(tile: tile)
                            .position(
                                x: controlFrame.minX + PlayerViewportLayout.storyboardPreviewX(
                                    time: previewTime,
                                    duration: player.duration,
                                    surfaceWidth: controlFrame.width
                                ),
                                y: max(
                                    58,
                                    controlFrame.maxY
                                        - PlayerViewportLayout.timelineBottomPadding(
                                            availableSize: controlFrame.size,
                                            isLandscape: isLandscape
                                        )
                                        - 68
                                )
                            )
                            .allowsHitTesting(false)
                    }
                    if let notice = player.sponsorBlockNotice {
                        SponsorBlockSkipOverlay(
                            notice: notice,
                            onUndo: { player.undoSponsorBlockSkip() },
                            onSkip: { player.confirmSponsorBlockSkip() },
                            onDismiss: { player.dismissSponsorBlockNotice() },
                            bottomPadding: PlayerViewportLayout.timelineBottomPadding(
                                availableSize: controlFrame.size,
                                isLandscape: isLandscape
                            ) + 46
                        )
                        .frame(width: controlFrame.width, height: controlFrame.height)
                        .position(x: controlFrame.midX, y: controlFrame.midY)
                    }
                }
                .frame(width: surfaceWidth, height: surfaceHeight)
                .onAppear { showPlayerControls() }
                .onDisappear { controlsVisibility.cancelAutoHide() }
                .onChange(of: player.currentVideo?.id) { _, _ in
                    gestureSeekPreview = nil
                    scrubberSeekPreview = nil
                    player.chapterListPresented = false
                    portraitVideoFullscreen = false
                    panelScrollOffset = 0
                    player.playerPanelAtTop = true
                    player.playerPanelGestureStartedAwayFromTop = false
                    if let videoID = player.currentVideo?.id {
                        detailsModel.reset(for: videoID)
                    }
                    showPlayerControls()
                }
                .onChange(of: player.loadState, initial: true) { _, state in
                    if state == .readyToPlay, player.isPlaying {
                        // The initial onAppear/current-video callbacks run while resolution is
                        // still pending, when showPlayerControls cannot schedule its hide timer.
                        // Readiness is the first reliable point at which playback can own it.
                        showPlayerControls()
                    }
                    guard state == .readyToPlay,
                          prefetchVideoDetails,
                          let video = player.currentVideo else { return }
                    detailsModel.loadIfNeeded(for: video, player: player)
            }
            if let video = player.currentVideo, !usesPortraitFullscreen {
                panel(
                    video,
                    collapseRange: collapseRange,
                    minimumContentHeight: max(
                        0,
                        proxy.size.height - compactSurfaceHeight + collapseRange
                    )
                )
                // Keep the previous landscape video/sidebar geometry. Only constrain the lower
                // metadata column so its title and rows cannot extend underneath Chapters.
                .frame(width: surfaceWidth, alignment: .leading)
            }
            }
            .frame(width: proxy.size.width, alignment: .leading)

            if player.chapterListPresented, !player.chapters.isEmpty, !usesPortraitFullscreen {
                PlayerChapterOverlay(
                    isLandscape: isLandscape,
                    usesOLEDBackground: oledPlayerBackground,
                    onInteraction: showPlayerControls
                )
                .frame(
                    width: isLandscape ? chapterPanelWidth : proxy.size.width,
                    height: isLandscape ? proxy.size.height : max(0, proxy.size.height - surfaceHeight)
                )
                .offset(y: isLandscape ? 0 : surfaceHeight)
                // Moving the landscape material sidebar while simultaneously widening the player
                // leaves a stale strip at the trailing edge for one render pass. Remove it
                // atomically and let the underlying column resize; portrait retains its sheet
                // transition because its geometry does not change horizontally.
                .transition(isLandscape ? .identity : .move(edge: .bottom))
                .zIndex(5)
            }
            }
        // One continuous material under EVERYTHING, including the top safe-area inset (status bar).
        // VStack content still respects safe area; only the material extends behind the inset.
        .background {
            if oledPlayerBackground {
                Color.black.ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.thinMaterial)
                    .ignoresSafeArea()
            }
        }
        // Ensure the system status bar stays visible with light glyphs against the dark material.
        .preferredColorScheme(.dark)
        .statusBarHidden(portraitFullscreenActive)
        // Presents UIActivityViewController for the "Open in…" menu action. Wrapping shareFileURL
        // in a `Binding<Bool>` that flips when the URL is set/cleared so the sheet lifecycle
        // matches the user's intent.
        .sheet(isPresented: Binding(
            get: { shareFileURL != nil },
            set: { if !$0 { shareFileURL = nil } }
        )) {
            if let url = shareFileURL {
                ActivityShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $saveToPlaylistVideo) { video in
            AddToPlaylistSheet(video: video)
        }
        .task(id: player.currentVideo?.id) {
            await actionsModel.refreshPlaylistMembership(for: player.currentVideo?.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task {
                await actionsModel.refreshPlaylistMembership(for: player.currentVideo?.id)
            }
        }
        .errorToast(Binding(
            get: { actionsModel.downloadError },
            set: { actionsModel.downloadError = $0 }
        ))
        .onChange(of: player.fullScreenPresented) { _, isPresented in
            if !isPresented {
                portraitVideoFullscreen = false
            }
        }
        .onChange(of: portraitFullscreenActive, initial: true) { _, isActive in
            player.playerPresentationGestureEnabled = !isActive
        }
        .onDisappear {
            player.playerPresentationGestureEnabled = true
        }

        // Make the VStack fill the GeometryReader's bounds. Without this, the VStack only
        // claims the natural content height (video + panel intrinsic
        // height) and the `.background { thinMaterial }` doesn't extend below that. On
        // smaller-than-content windows (Mac shrunk) this is invisible; on larger ones
        // (Mac maximized) you'd see an unfilled gap below the panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Lower section

    private func toggleFullscreen() {
        if isPortraitVideo {
            withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                portraitVideoFullscreen.toggle()
                player.chapterListPresented = false
            }
            if portraitVideoFullscreen {
                requestPlayerOrientation(.portrait)
            }
        } else {
            requestPlayerOrientation(verticalSizeClass == .compact ? .portrait : .landscapeRight)
        }
        showPlayerControls()
    }

    private var portraitFullscreenActive: Bool {
        portraitVideoFullscreen && isPortraitVideo && verticalSizeClass != .compact
    }

    private var isPortraitVideo: Bool {
        let size = player.videoPresentationSize
        if size.width > 0, size.height > 0 { return size.height > size.width }
        return player.currentVideo?.isShort == true
    }

    private func requestPlayerOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// Default panel mode. No NavigationStack wrapping — the outer popup's `.thinMaterial`
    /// shows through directly behind metadata, Up Next, and Comments.
    @ViewBuilder
    private func panel(
        _ video: Video,
        collapseRange: CGFloat,
        minimumContentHeight: CGFloat
    ) -> some View {
        if #available(iOS 18.0, *) {
            panelScrollView(
                video,
                collapseRange: collapseRange,
                minimumContentHeight: minimumContentHeight
            )
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    panelScrollOffset = offset
                    player.playerPanelAtTop = offset <= 0.5
                }
        } else {
            panelScrollView(
                video,
                collapseRange: collapseRange,
                minimumContentHeight: minimumContentHeight
            )
                .coordinateSpace(name: "playerPanelScroll")
                .onPreferenceChange(PlayerPanelScrollOffsetKey.self) { offset in
                    panelScrollOffset = offset
                    player.playerPanelAtTop = offset <= 0.5
                }
        }
    }

    private func panelScrollView(
        _ video: Video,
        collapseRange: CGFloat,
        minimumContentHeight: CGFloat
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear
                    // Keep the geometry probe alive so it reliably emits scroll preferences.
                    .frame(height: 1)
                    .reportPlayerPanelScrollOffset()
                PlayerInformationPanel(
                    video: video,
                    statsText: detailsModel.statsText(for: video),
                    descriptionText: detailsModel.description(for: video),
                    descriptionParts: detailsModel.details?.descriptionParts ?? [],
                    likesText: detailsModel.likesText,
                    commentsCountText: detailsModel.commentsCountText(
                        fallback: player.commentsCountText
                    ),
                    isDetailsExpanded: detailsModel.isExpanded,
                    isLoadingDetails: detailsModel.isLoading,
                    detailsLoadFailed: detailsModel.loadFailed,
                    showsUpNext: showUpNext,
                    upNextInitialCount: upNextInitialCount,
                    showsComments: showComments,
                    onToggleDetails: {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            detailsModel.isExpanded.toggle()
                        }
                        if detailsModel.isExpanded {
                            detailsModel.loadIfNeeded(for: video, player: player)
                        }
                    },
                    onExpandDetails: {
                        withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                            detailsModel.isExpanded = true
                        }
                        detailsModel.loadIfNeeded(for: video, player: player)
                    },
                    onRetryDetails: {
                        detailsModel.retry(for: video, player: player)
                    },
                    onOpenChannel: {
                        openChannel(video.channelID)
                    },
                    onSeek: { player.seek(to: $0) },
                    onOpenPlaylist: openPlaylist
                ) {
                    playerActions(video)
                }
            }
            .padding(.top, 6)
            .padding(.bottom)
            // While the header is collapsing, counteract the ScrollView's own content movement.
            // Use real padding rather than a visual offset: an offset does not enlarge the
            // ScrollView's measured content and made the final comments unreachable by exactly
            // this compensation distance.
            .padding(.top, min(max(panelScrollOffset, 0), collapseRange))
            // Preserve enough scroll extent to consume the complete header collapse even when
            // comments and Up Next are both collapsed and the natural feed is very short.
            .frame(minHeight: minimumContentHeight, alignment: .top)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    guard !panelScrollGestureActive else { return }
                    panelScrollGestureActive = true
                    player.playerPanelGestureStartedAwayFromTop = panelScrollOffset > 0.5
                }
                .onEnded { _ in
                    panelScrollGestureActive = false
                    player.playerPanelGestureStartedAwayFromTop = false
                }
        )
        .scrollDisabled(player.playerPresentationGestureActive)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Player actions

    @ViewBuilder
    private func playerActions(_ video: Video) -> some View {
        let videoURL = watchURL(video)
        let downloadedFileURL = actionsModel.downloadedFile(for: video.id)
        PlayerActionBar(
            isSavedToPlaylist: actionsModel.isSavedToPersonalPlaylist,
            watchURL: videoURL,
            downloadedFileURL: downloadedFileURL,
            downloadState: actionsModel.downloadState(
                for: video.id,
                downloadedFileURL: downloadedFileURL
            ),
            onSaveToPlaylist: {
                saveToPlaylistVideo = video
            },
            onCopyURL: {
                if let videoURL {
                    UIPasteboard.general.string = videoURL.absoluteString
                }
            },
            onCopyURLAtCurrentTime: {
                if let url = watchURLAtCurrentTime(video) {
                    UIPasteboard.general.string = url.absoluteString
                }
            },
            onShareDownloadedFile: {
                shareFileURL = downloadedFileURL
            },
            onDownload: {
                actionsModel.startDownload(video)
            }
        )
    }

    // MARK: - Transport

    private func togglePlayerControls() {
        controlsVisibility.toggle(
            isPlaying: player.isPlaying,
            reduceMotion: reduceMotion
        )
    }

    private func showPlayerControls() {
        controlsVisibility.show(
            isPlaying: player.isPlaying,
            reduceMotion: reduceMotion
        )
    }

    private var hasPrevious: Bool {
        player.canPlayPrevious
    }

    private var hasNext: Bool {
        player.canPlayNext
    }

    private var visiblePlayerTopControls: [PlayerTopControl] {
        let hidden = PlayerTopControl.decodeHidden(hiddenPlayerTopControlsRaw)
        return PlayerTopControl.decodeOrder(playerTopControlOrderRaw).filter { !hidden.contains($0) }
    }

    private func watchURL(_ video: Video) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=\(video.id)")
    }

    /// `youtu.be/<id>?t=<seconds>` is the canonical share-with-timestamp URL YouTube understands.
    private func watchURLAtCurrentTime(_ video: Video) -> URL? {
        let seconds = Int(player.elapsed)
        return URL(string: "https://youtu.be/\(video.id)?t=\(seconds)")
            ?? URL(string: "https://youtu.be/\(video.id)")
    }

    private func openChannel(_ channelID: String) {
        @Bindable var p = player
        p.fullScreenPresented = false
        Task { @MainActor in
            // Let the SwiftUI collapse animation begin before routing the tab below.
            try? await Task.sleep(for: .milliseconds(180))
            NotificationCenter.default.post(name: .freetubeOpenChannel, object: channelID)
        }
    }

    private func openPlaylist(_ playlistID: String) {
        player.fullScreenPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if playlistID.hasPrefix("local:") {
                NotificationCenter.default.post(
                    name: .freetubeOpenLocalPlaylist,
                    object: String(playlistID.dropFirst("local:".count))
                )
            } else {
                NotificationCenter.default.post(name: .freetubeOpenPlaylist, object: playlistID)
            }
        }
    }

}
