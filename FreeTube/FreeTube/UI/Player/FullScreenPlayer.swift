import SwiftUI
import UIKit

/// Expanded player content hosted by the app's SwiftUI player container. This view renders the
/// surface, transport controls, metadata, and independently collapsible sections below.
@available(iOS 17.0, *)
struct FullScreenPlayer: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var downloads = DownloadManager.shared

    /// Async-loaded description / details for the currently-playing video. Fetched on demand when
    /// the user taps "More" under the channel row.
    @State private var details: VideoInfo?
    /// Are we currently fetching `details`? Drives the spinner in the description area.
    @State private var isLoadingDetails = false
    @State private var detailsLoadFailed = false
    /// True when the user has expanded the description block — shows full text instead of a
    /// truncated preview, and tries to load extended details (tags etc.) if not yet loaded.
    @State private var isDetailsExpanded = false
    /// File URL the user wants to hand off to another app via the system "Open in…" share sheet.
    /// Non-nil → present the activity controller; tapped row sets this, sheet dismissal clears it.
    @State private var shareFileURL: URL?
    @State private var saveToPlaylistVideo: Video?
    @State private var isSavedToPersonalPlaylist = false
    @State private var downloadError: ErrorState?
    /// Currently-pushed channel (nil = panel mode). When non-nil, the lower section swaps the
    /// metadata + comments/queue panel for a NavigationStack rooted at `ChannelScreen`. Keeping
    /// the NavigationStack **conditionally mounted** is what makes the panel-mode background
    /// match the transport row: SwiftUI's NavigationStack container paints opaque under its
    /// content, so any thinMaterial inside it stacks on top of an opaque layer and reads darker
    /// than the rest of the popup. With the stack absent in panel mode, the outer VStack's
    /// thinMaterial paints through cleanly.
    @State private var pushedChannel: ChannelPresentation?
    /// Path for deeper pushes inside the channel flow (e.g. ChannelScreen → ChannelTabScreen).
    /// Only meaningful while `pushedChannel != nil`.
    @State private var channelPath = NavigationPath()
    @State private var playerControlsVisible = true
    @State private var gestureSeekPreview: TimeInterval?
    @State private var scrubberSeekPreview: TimeInterval?
    @State private var panelScrollOffset: CGFloat = 0
    @State private var panelScrollGestureActive = false
    @State private var controlsHideTask: Task<Void, Never>?
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

    /// Hashable wrapper so `.navigationDestination(for:)` can match the channel id and push
    /// `ChannelScreen` onto `channelPath`.
    struct ChannelPresentation: Identifiable, Hashable {
        let id: String
    }

    var body: some View {
        // Single dark-blur material under EVERYTHING — status bar inset, video chrome, transport,
        // comments, queue. Removing per-section backgrounds and using one full-screen material lets
        // the popup read as one continuous translucent surface instead of three stacked tones.
        //
        // The outer GeometryReader provides a stable viewport for both the display-correct
        // expanded ratio and the compact 16:9 ratio. Their difference becomes the first part of
        // the lower panel's scroll range, allowing a tall player to behave as a collapsible header.
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
                : surfaceWidth * 9 / 16
            let expandedSurfaceHeight = usesPortraitFullscreen || isLandscape
                ? compactSurfaceHeight
                : expandedPlayerSurfaceHeight(
                    width: surfaceWidth,
                    viewportHeight: proxy.size.height
                )
            let collapseRange = usesPortraitFullscreen
                ? 0
                : max(0, expandedSurfaceHeight - compactSurfaceHeight)
            let consumedCollapse = min(max(panelScrollOffset, 0), collapseRange)
            let surfaceHeight = expandedSurfaceHeight - consumedCollapse
            let controlFrame = playerControlFrame(
                surfaceSize: CGSize(width: surfaceWidth, height: surfaceHeight),
                isLandscape: isLandscape,
                hasChapterSidebar: chapterPanelWidth > 0
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
                        .opacity(playerControlsVisible ? 0.28 : 0)
                        // Dim the stable player surface rather than AVPlayer's presentation rect.
                        // The latter changes from unknown/full-size to the decoded aspect ratio
                        // as a new item becomes ready, which made non-16:9 videos flash unevenly.
                        // Letterbox pixels are already black, so covering them has no visible cost.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    CustomPlayerControls(
                        isVisible: playerControlsVisible,
                        isSeekPreviewActive: gestureSeekPreview != nil || scrubberSeekPreview != nil,
                        isPlaying: player.isPlaying,
                        hasEnded: player.hasEnded,
                        elapsed: scrubberSeekPreview ?? gestureSeekPreview ?? player.elapsed,
                        duration: player.duration,
                        isLive: player.currentVideo?.isLive == true,
                        sponsorSegments: player.sponsorBlockSegments,
                        chapters: player.chapters,
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
                        bottomTimelinePadding: timelineBottomPadding(
                            in: controlFrame.size
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
                            withAnimation(.snappy(duration: 0.28)) {
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
                                x: controlFrame.minX + storyboardPreviewX(
                                    for: previewTime,
                                    duration: player.duration,
                                    surfaceWidth: controlFrame.width
                                ),
                                y: max(
                                    58,
                                    controlFrame.maxY
                                        - timelineBottomPadding(
                                            in: controlFrame.size
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
                            bottomPadding: timelineBottomPadding(
                                in: controlFrame.size
                            ) + 46
                        )
                        .frame(width: controlFrame.width, height: controlFrame.height)
                        .position(x: controlFrame.midX, y: controlFrame.midY)
                    }
                }
                .frame(width: surfaceWidth, height: surfaceHeight)
                .onAppear { showPlayerControls() }
                .onDisappear { controlsHideTask?.cancel() }
                .onChange(of: player.currentVideo?.id) { _, _ in
                    gestureSeekPreview = nil
                    scrubberSeekPreview = nil
                    player.chapterListPresented = false
                    portraitVideoFullscreen = false
                    panelScrollOffset = 0
                    player.playerPanelAtTop = true
                    player.playerPanelGestureStartedAwayFromTop = false
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
                    loadDetailsIfNeeded(for: video)
                }
            if let video = player.currentVideo, !usesPortraitFullscreen {
                // **Two render modes for the lower section, picked by `pushedChannel`:**
                //
                // 1. **Panel mode (default, channel == nil):** plain ScrollView, NO
                //    NavigationStack. The outer VStack's `.background { thinMaterial }` paints
                //    behind it directly — exactly the same backdrop the transport row above
                //    shows. This is what makes the visual treatment consistent.
                //
                // 2. **Channel-pushed mode (channel != nil):** NavigationStack rooted at
                //    `ChannelScreen`, with its own thinMaterial inside since the stack's UIKit
                //    container paints opaque. Channel's own internal NavigationLinks (to
                //    ChannelTabScreen / PlaylistScreen) push further into this stack.
                //
                // The previous version kept the NavigationStack mounted in both modes — that
                // forced us to paint an inner thinMaterial under the comments/queue panel,
                // which stacked on top of the stack's opaque container and read noticeably
                // darker than the transport row. Mounting the stack only when needed fixes it.
                Group {
                    if let channel = pushedChannel {
                        channelStack(channel)
                    } else {
                        panel(
                            video,
                            collapseRange: collapseRange,
                            minimumContentHeight: max(
                                0,
                                proxy.size.height - compactSurfaceHeight + collapseRange
                            )
                        )
                    }
                }
                // Reset description state, (best-effort) prefetch the snippet, AND pop any
                // pushed channel screen whenever the user picks a new video — otherwise tapping
                // the next video in the queue would leave a stale channel push on screen.
                .onChange(of: video.id) { _, _ in
                    details = nil
                    isDetailsExpanded = false
                    detailsLoadFailed = false
                    pushedChannel = nil
                    channelPath = NavigationPath()
                    prefetchDescriptionIfAvailable(for: video)
                }
                // Keep the previous landscape video/sidebar geometry. Only constrain the lower
                // metadata column so its title and rows cannot extend underneath Chapters.
                .frame(width: surfaceWidth, alignment: .leading)
            }
            }
            .frame(width: proxy.size.width, alignment: .leading)

            if player.chapterListPresented, !player.chapters.isEmpty, !usesPortraitFullscreen {
                ChapterListPanel(
                    chapters: player.chapters,
                    elapsed: player.elapsed,
                    isLandscape: isLandscape,
                    usesOLEDBackground: oledPlayerBackground,
                    onSeek: { target in
                        player.seek(to: target)
                        showPlayerControls()
                    },
                    onDismiss: {
                        withAnimation(.snappy(duration: 0.28)) {
                            player.chapterListPresented = false
                        }
                    }
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
            await refreshPersonalPlaylistMembership()
        }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { await refreshPersonalPlaylistMembership() }
        }
        .errorToast($downloadError)
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

    // MARK: - Lower section: panel vs channel-push

    /// The video remains full-width in landscape. When its 16:9 height exceeds a short phone
    /// viewport, lift only the timeline by that overflow so the picture geometry does not change.
    private func timelineBottomPadding(in availableSize: CGSize) -> CGFloat {
        if verticalSizeClass == .compact { return 16 }
        let aspectHeight = availableSize.width * 9 / 16
        return max(8, aspectHeight - availableSize.height + 16)
    }

    /// Keeps landscape chrome inside the visible widescreen picture and outside the notch. Tall
    /// videos deliberately retain the complete safe width so their controls remain usable rather
    /// than being squeezed into the narrow portrait image at the centre of a landscape display.
    private func playerControlFrame(
        surfaceSize: CGSize,
        isLandscape: Bool,
        hasChapterSidebar: Bool
    ) -> CGRect {
        let full = CGRect(origin: .zero, size: surfaceSize)
        guard isLandscape, surfaceSize.width > 0, surfaceSize.height > 0 else { return full }

        let insets = PlayerLayoutMetrics.safeAreaInsets
        let safeMinX = min(surfaceSize.width, insets.left)
        let safeMaxX = max(safeMinX, surfaceSize.width - (hasChapterSidebar ? 0 : insets.right))
        let safeWidth = safeMaxX - safeMinX
        let presentation = player.videoPresentationSize
        let isTallVideo = presentation.width > 0
            && presentation.height > 0
            && presentation.height > presentation.width
        guard !isTallVideo else {
            return CGRect(x: safeMinX, y: 0, width: safeWidth, height: surfaceSize.height)
        }

        let aspect = presentation.width > 0 && presentation.height > 0
            ? presentation.width / presentation.height
            : 16 / 9
        let fittedWidth = min(safeWidth, surfaceSize.height * aspect)
        return CGRect(
            x: safeMinX + (safeWidth - fittedWidth) / 2,
            y: 0,
            width: fittedWidth,
            height: surfaceSize.height
        )
    }

    /// Uses AVPlayer's display-correct dimensions for portrait/tall media. Tall videos start at
    /// their natural ratio (bounded so some feed remains reachable), then smoothly compress toward
    /// the familiar 16:9 player as the lower panel scrolls, matching YouTube's expanding header.
    private func expandedPlayerSurfaceHeight(width: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let compactHeight = width * 9 / 16
        let size = player.videoPresentationSize
        guard verticalSizeClass != .compact,
              size.width > 0, size.height > 0 else { return compactHeight }
        let naturalHeight = width * size.height / size.width
        return min(max(naturalHeight, compactHeight), viewportHeight * 0.72)
    }

    /// Tracks the timeline thumb while keeping the 116pt-wide preview plus edge clearance
    /// wholly inside the player surface at both ends of the video.
    private func storyboardPreviewX(
        for time: TimeInterval,
        duration: TimeInterval,
        surfaceWidth: CGFloat
    ) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite, surfaceWidth > 0 else {
            return surfaceWidth / 2
        }
        let fraction = min(max(time / duration, 0), 1)
        let trackX = 12 + (surfaceWidth - 24) * CGFloat(fraction)
        let minimumCenterX: CGFloat = 66
        guard surfaceWidth >= minimumCenterX * 2 else { return surfaceWidth / 2 }
        return min(max(trackX, minimumCenterX), surfaceWidth - minimumCenterX)
    }

    private func toggleFullscreen() {
        if isPortraitVideo {
            withAnimation(.smooth(duration: 0.3)) {
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
                metadata(video)
                detailsSection(video: video)
                PlayerQueueSections(
                    showsUpNext: showUpNext,
                    upNextInitialCount: upNextInitialCount,
                    onOpenPlaylist: openPlaylist
                )
                if showComments {
                    CommentsSection(
                        videoID: video.id,
                        countText: details?.commentsCountText ?? player.commentsCountText
                    )
                        .id(video.id)
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

    /// NavigationStack rooted at `ChannelScreen`. Mounted only when `pushedChannel != nil`.
    /// Internal `NavigationLink`s inside `ChannelScreen` push onto `channelPath`; popping the
    /// last item via our back button returns to panel mode.
    @ViewBuilder
    private func channelStack(_ root: ChannelPresentation) -> some View {
        NavigationStack(path: $channelPath) {
            channelDestination(root, isRoot: true)
                .navigationDestination(for: ChannelPresentation.self) { channel in
                    channelDestination(channel, isRoot: false)
                }
        }
    }

    /// Single channel destination — used for both the root channel (pushed from the player) and
    /// any further pushes via NavigationLink. The back button pops `channelPath` when there's
    /// something on it, otherwise clears `pushedChannel` to return to panel mode.
    @ViewBuilder
    private func channelDestination(_ channel: ChannelPresentation, isRoot: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ChannelScreen(channelID: channel.id)
                .toolbar(.hidden, for: .navigationBar)
                // Solid black, matching the playlist push inside this same NavigationStack.
                // We deliberately don't use `.thinMaterial` here — pushed destinations inside
                // the popup body use opaque black for visual consistency with PlaylistScreen,
                // while the panel-mode comments/queue area keeps the popup's outer thinMaterial.
                .background {
                    Color.black.ignoresSafeArea()
                }

            Button {
                if !channelPath.isEmpty {
                    channelPath.removeLast()
                } else {
                    pushedChannel = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.top, 8)
        }
    }

    // MARK: - Metadata

    @ViewBuilder
    private func metadata(_ video: Video) -> some View {
        PlayerMetadataHeader(
            video: video,
            statsText: detailsStatsRow(video: video),
            isDetailsExpanded: isDetailsExpanded,
            canOpenChannel: !video.channelID.isEmpty,
            onToggleDetails: {
                withAnimation(.smooth(duration: 0.24)) {
                    isDetailsExpanded.toggle()
                }
                if isDetailsExpanded {
                    loadDetailsIfNeeded(for: video)
                }
            },
            onOpenChannel: {
                @Bindable var p = player
                p.fullScreenPresented = false
                let channelID = video.channelID
                Task { @MainActor in
                    // Let the SwiftUI collapse animation begin before routing the tab below.
                    try? await Task.sleep(for: .milliseconds(180))
                    NotificationCenter.default.post(
                        name: .freetubeOpenChannel,
                        object: channelID
                    )
                }
            }
        ) {
            playerActions(video)
        }
    }

    // MARK: - Description / details (between channel row and comments)

    /// Shows the video description in a YouTube-like collapsed-by-default block. Tapping the video
    /// title expands it and lazily fetches the full details payload.
    private func detailsSection(video: Video) -> some View {
        PlayerDescription(
            text: availableDescription(video: video),
            parts: details?.descriptionParts ?? [],
            likesText: (details?.likeCount).flatMap { $0 > 0 ? formatCount($0) : nil },
            isExpanded: isDetailsExpanded,
            isLoading: isLoadingDetails,
            loadFailed: detailsLoadFailed,
            onSeek: { player.seek(to: $0) },
            onRetry: {
                details = nil
                loadDetailsIfNeeded(for: video)
            },
            onExpand: {
                withAnimation(.smooth(duration: 0.24)) { isDetailsExpanded = true }
                loadDetailsIfNeeded(for: video)
            }
        )
    }

    /// Picks the description text to render in the 2-line collapsed preview. Prefer the loaded
    /// details (more complete), fall back to the search-result snippet.
    private func inlineDescriptionSnippet(video: Video) -> String? {
        availableDescription(video: video)
    }

    private func availableDescription(video: Video) -> String? {
        if let fetched = details?.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fetched.isEmpty {
            return fetched
        }
        if let snippet = video.descriptionSnippet?.trimmingCharacters(in: .whitespacesAndNewlines),
           !snippet.isEmpty {
            return snippet
        }
        return nil
    }

    /// `42K views • Uploaded 3 days ago`, omitting any pieces we don't have.
    private func detailsStatsRow(video: Video) -> String {
        var parts: [String] = []
        if let viewsText = details?.viewCountText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !viewsText.isEmpty {
            parts.append(viewsText)
        } else if let views = video.viewCount, views > 0 {
            parts.append("\(formatCount(views)) views")
        }
        if let uploadDateText = details?.uploadDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uploadDateText.isEmpty {
            parts.append("Uploaded \(uploadDateText)")
        } else if let published = video.publishedAt {
            parts.append("Uploaded \(published.formatted(date: .abbreviated, time: .omitted))")
        } else if let relative = video.publishedRelative, !relative.isEmpty {
            parts.append("Uploaded \(relative)")
        }
        return parts.joined(separator: " • ")
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Best-effort: if `descriptionSnippet` is already on the `Video` (from search/home), we have
    /// something to show without hitting the network. Don't preemptively fetch the full details —
    /// the user might never tap "More".
    private func prefetchDescriptionIfAvailable(for video: Video) {
        // Intentional no-op. The fetch happens on the user's first "More" tap.
        _ = video
    }

    /// Lazy fetch invoked when the user expands the description. One `VideoService.fetchMoreInfo`
    /// call per video; subsequent expansions reuse the cached result in `details`.
    private func loadDetailsIfNeeded(for video: Video) {
        guard details == nil, !isLoadingDetails else { return }
        isLoadingDetails = true
        detailsLoadFailed = false
        Task { [videoID = video.id] in
            defer { Task { @MainActor in isLoadingDetails = false } }
            do {
                let info = try await VideoContentPrefetchStore.shared.fetchDetails(videoID: videoID)
                await MainActor.run {
                    // Drop the result if the user switched videos before this returned.
                    guard player.currentVideo?.id == videoID else { return }
                    details = info
                    player.installVideoDetails(info, for: videoID)
                    let fetched = info.descriptionText?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let snippet = video.descriptionSnippet?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    detailsLoadFailed = (fetched?.isEmpty ?? true) && (snippet?.isEmpty ?? true)
                }
            } catch {
                await MainActor.run {
                    guard player.currentVideo?.id == videoID else { return }
                    detailsLoadFailed = true
                }
            }
        }
    }

    // MARK: - Player actions

    @ViewBuilder
    private func playerActions(_ video: Video) -> some View {
        let videoURL = watchURL(video)
        let currentTimeURL = watchURLAtCurrentTime(video)
        let downloadedFileURL = downloads.localFile(for: video.id)
        PlayerActionBar(
            isSavedToPlaylist: isSavedToPersonalPlaylist,
            watchURL: videoURL,
            downloadedFileURL: downloadedFileURL,
            downloadState: downloadPresentationState(
                for: video,
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
                if let currentTimeURL {
                    UIPasteboard.general.string = currentTimeURL.absoluteString
                }
            },
            onShareDownloadedFile: {
                shareFileURL = downloadedFileURL
            },
            onDownload: {
                startDownload(video)
            }
        )
    }

    private func refreshPersonalPlaylistMembership() async {
        guard let videoID = player.currentVideo?.id else {
            isSavedToPersonalPlaylist = false
            return
        }
        let isSaved = await LocalPlaylistService().isInPersonalPlaylist(videoID: videoID)
        guard player.currentVideo?.id == videoID else { return }
        isSavedToPersonalPlaylist = isSaved
    }

    private func downloadPresentationState(
        for video: Video,
        downloadedFileURL: URL?
    ) -> PlayerDownloadPresentationState {
        if downloadedFileURL != nil { return .downloaded }
        if isDownloadActive(for: video) { return .downloading }
        return .available
    }

    private func isDownloadActive(for video: Video) -> Bool {
        downloads.activeTasks.contains { snapshot in
            guard snapshot.videoID == video.id else { return false }
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }
    }

    private func startDownload(_ video: Video) {
        let quality = UserPreferences().preferredQuality
        Task {
            do {
                _ = try await downloads.ensureDownloaded(video: video, quality: quality)
            } catch {
                downloadError = ErrorState(from: error)
            }
        }
    }

    // MARK: - Transport

    private func togglePlayerControls() {
        playerControlsVisible ? hidePlayerControls() : showPlayerControls()
    }

    private func showPlayerControls() {
        controlsHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { playerControlsVisible = true }
        guard player.isPlaying else { return }
        controlsHideTask = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled else { return }
            hidePlayerControls()
        }
    }

    private func hidePlayerControls() {
        controlsHideTask?.cancel()
        controlsHideTask = nil
        withAnimation(.easeIn(duration: 0.18)) { playerControlsVisible = false }
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
