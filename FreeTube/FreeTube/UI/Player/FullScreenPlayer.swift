import SwiftUI
import UIKit

import Kingfisher

/// Expanded player content presented by `LNPopupUI` when the popup bar is opened. The popup chrome
/// (close button) is provided by the library — this view renders the surface, transport controls,
/// metadata, plus independently collapsible Up Next and Comments sections below.
@available(iOS 17.0, *)
struct FullScreenPlayer: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var downloads = DownloadManager.shared

    /// Keep recommendation rows out of the render tree until the user asks to inspect them.
    @State private var isQueueExpanded = false
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
    @State private var controlsHideTask: Task<Void, Never>?
    @AppStorage("autoplayNext") private var autoplayNext = true

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
        // **Why the outer `GeometryReader`:** we want the video to always be full-width
        // regardless of how wide vs tall the popup is. `.aspectRatio(16/9, .fit)` clamps the
        // video to whichever dimension is tighter — on iPhone portrait that's always width
        // (the screen is much taller than 16:9), but on Mac (Designed-for-iPad) and iPad
        // landscape the window is wider than 16:9 so `.fit` height-clamps and the video sits
        // letterboxed inside black side bars. Reading the available width via
        // `GeometryReader` and sizing the ZStack to `proxy.size.width × width*9/16`
        // explicitly removes the clamp — full-width on every idiom.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // Pinning the ZStack to width × width*9/16 keeps the surface a stable height
                // across .resolving → .downloading → .readyToPlay (the underlying
                // AVPlayerViewController has zero intrinsic size while loading; the explicit
                // frame here is what stops the layout from jumping when the user taps a queue
                // item).
                // Layer order is load-bearing. `AVPlayerViewController` paints an opaque black
                // background, so the thumbnail has to sit *above* `PlayerSurface` to be visible at
                // all — it hides itself once `loadState` reaches `.readyToPlay`. The `.animation`
                // on the container is what turns that hand-off into a crossfade instead of a cut.
                ZStack {
                    Color.black
                    PlayerSurface(
                        player: player.player,
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
                        onToggleControls: { togglePlayerControls() }
                    )
                    PlayerArtworkBackdrop(artwork: player.currentArtwork, state: player.loadState)
                    DownloadProgressOverlay(state: player.loadState)
                    CustomPlayerControls(
                        isVisible: playerControlsVisible,
                        isSeekPreviewActive: gestureSeekPreview != nil,
                        isPlaying: player.isPlaying,
                        elapsed: gestureSeekPreview ?? player.elapsed,
                        duration: player.duration,
                        playbackRate: player.playbackRate,
                        playbackQuality: player.playbackQuality,
                        sponsorSegments: player.sponsorBlockSegments,
                        hasPrevious: hasPrevious,
                        hasNext: hasNext,
                        additionalTopControls: AnyView(
                            fullscreenButton
                            .buttonStyle(.plain)
                        ),
                        bottomTimelinePadding: timelineBottomPadding(in: proxy.size),
                        onTogglePlayPause: {
                            player.togglePlayPause()
                            showPlayerControls()
                        },
                        onSeek: {
                            player.seek(to: $0)
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
                        onSetRate: {
                            player.setPlaybackRate($0)
                            showPlayerControls()
                        },
                        onSetQuality: {
                            player.setPlaybackQuality($0)
                            showPlayerControls()
                        },
                        onCollapse: {
                            @Bindable var p = player
                            p.fullScreenPresented = false
                        }
                    )
                    if let notice = player.sponsorBlockNotice {
                        SponsorBlockSkipOverlay(
                            notice: notice,
                            onUndo: { player.undoSponsorBlockSkip() },
                            onSkip: { player.confirmSponsorBlockSkip() },
                            onDismiss: { player.dismissSponsorBlockNotice() },
                            bottomPadding: timelineBottomPadding(in: proxy.size) + 46
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.width * 9 / 16)
                .animation(.easeOut(duration: 0.2), value: player.loadState)
                .onAppear { showPlayerControls() }
                .onDisappear { controlsHideTask?.cancel() }
                .onChange(of: player.currentVideo?.id) { _, _ in
                    gestureSeekPreview = nil
                    showPlayerControls()
                }
            // Pull-down-to-dismiss starting from the video surface.
            //
            // `AVPlayerViewController`'s internal `UIPanGestureRecognizer`s (scrubber, system
            // controls) consume touches before they can reach LNPopupUI's outer pan, so the
            // library's `.popupInteractionStyle(.drag)` only works when the gesture starts on
            // SwiftUI views below the video (comments / queue). `.simultaneousGesture` is the
            // escape hatch: SwiftUI composes this `DragGesture` with the UIKit recognizers
            // underneath instead of arbitrating between them, so AVPlayerViewController's
            // controls keep working AND we can detect a downward pull and dismiss the popup
            // imperatively. LNPopupUI animates the collapse — we just flip the binding.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .global)
                    .onEnded { value in
                        let mostlyDown = value.translation.height > 90
                            && abs(value.translation.width) < value.translation.height
                        let fastFlick = value.predictedEndTranslation.height > 180
                        if mostlyDown || fastFlick {
                            @Bindable var p = player
                            p.fullScreenPresented = false
                        }
                    }
            )

            if let video = player.currentVideo {
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
                        panel(video)
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
            }
        }
        // One continuous material under EVERYTHING, including the top safe-area inset (status bar).
        // VStack content still respects safe area; only the material extends behind the inset.
        .background {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()
        }
        // Ensure the system status bar stays visible and gets light-content (white) glyphs against
        // the dark material. LNPopupUI's `LNPopupContentHostingController` is a UIHostingController
        // subclass that doesn't override status bar style, so SwiftUI's colorScheme drives it.
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
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
        .errorToast($downloadError)
        // Pull-down-to-dismiss is handled by LNPopupUI via `.popupInteractionStyle(...)` in
        // RootView. We don't install a custom DragGesture here — it would race with the system
        // gesture arbitration the popup hosts (and with AVPlayerViewController's own touch
        // handling once the video surface goes interactive). That was the bug where the
        // expanded player wouldn't visibly follow the finger during a downward swipe once
        // playback started; the close was only happening on touch-up.

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
        let aspectHeight = availableSize.width * 9 / 16
        guard verticalSizeClass == .compact else { return 8 }
        return max(22, aspectHeight - availableSize.height + 16)
    }

    @ViewBuilder
    private var fullscreenButton: some View {
        Button {
            requestPlayerOrientation(verticalSizeClass == .compact ? .portrait : .landscapeRight)
            showPlayerControls()
        } label: {
            Image(systemName: verticalSizeClass == .compact
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        }
        .accessibilityLabel(verticalSizeClass == .compact ? "Exit fullscreen" : "Enter fullscreen")
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
    private func panel(_ video: Video) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadata(video)
                playerActions(video)
                detailsSection(video: video)
                queuePanel
                CommentsSection(videoID: video.id)
                    .id(video.id)
            }
            .padding(.vertical)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDetailsExpanded.toggle()
                }
                if isDetailsExpanded {
                    loadDetailsIfNeeded(for: video)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(video.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isDetailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Tapping anywhere on the channel row pushes the channel detail screen onto the
            // popup's internal NavigationStack — banner, subscribe button, latest videos,
            // shorts, playlists. Pushing (rather than presenting) keeps the video surface and
            // transport controls visible at the top; only the panel area below is replaced.
            if !video.channelID.isEmpty {
                Button {
                    @Bindable var p = player
                    p.fullScreenPresented = false
                    let channelID = video.channelID
                    Task { @MainActor in
                        // Let LNPopupUI begin its collapse before presenting a new full-screen
                        // controller; presenting both in the same transaction is ignored by UIKit.
                        try? await Task.sleep(for: .milliseconds(180))
                        NotificationCenter.default.post(
                            name: .freetubeOpenChannel,
                            object: channelID
                        )
                    }
                } label: {
                    channelRow(video)
                }
                .buttonStyle(.plain)
            } else {
                channelRow(video)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func channelRow(_ video: Video) -> some View {
        HStack(spacing: 12) {
            KFImage(video.channelThumbnailURL)
                .thumbnail(size: CGSize(width: 32, height: 32)) {
                    Circle().fill(.gray.opacity(0.2))
                }
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            Text(video.channelName).font(.subheadline)
            Spacer()
        }
    }

    // MARK: - Description / details (between channel row and comments)

    /// Shows the video description in a YouTube-like collapsed-by-default block. Tapping the video
    /// title expands it and lazily fetches the full details payload.
    @ViewBuilder
    private func detailsSection(video: Video) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDetailsExpanded {
                expandedDetailsBody(video: video)
            } else {
                collapsedDetailsBody(video: video)
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: isDetailsExpanded)
    }

    @ViewBuilder
    private func collapsedDetailsBody(video: Video) -> some View {
        if let snippet = inlineDescriptionSnippet(video: video) {
            Text(snippet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func expandedDetailsBody(video: Video) -> some View {
        // Full description text (from the loaded details, falling back to the search-result snippet).
        if let text = availableDescription(video: video) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        } else if isLoadingDetails {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading details…").font(.caption).foregroundStyle(.secondary)
            }
        } else if detailsLoadFailed {
            HStack(spacing: 8) {
                Text("Description unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    details = nil
                    loadDetailsIfNeeded(for: video)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }

        // Quick stats line: views • explicitly labelled upload date.
        let statsRow = detailsStatsRow(video: video)
        if !statsRow.isEmpty {
            Text(statsRow)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Like count if we got it from the details payload.
        if let likes = details?.likeCount, likes > 0 {
            Text("\(formatCount(likes)) likes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

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
        if let views = video.viewCount, views > 0 {
            parts.append("\(formatCount(views)) views")
        }
        if let published = video.publishedAt {
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
                let info = try await VideoService().fetchMoreInfo(id: videoID)
                await MainActor.run {
                    // Drop the result if the user switched videos before this returned.
                    guard player.currentVideo?.id == videoID else { return }
                    details = info
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
        HStack(spacing: 12) {
            Menu {
                if let url = watchURL(video) {
                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                    } label: {
                        Label("Copy URL", systemImage: "link")
                    }
                }
                Button {
                    if let url = watchURLAtCurrentTime(video) {
                        UIPasteboard.general.string = url.absoluteString
                    }
                } label: {
                    Label("Copy URL at current time", systemImage: "clock")
                }
                if let localFile = downloads.localFile(for: video.id) {
                    Button {
                        shareFileURL = localFile
                    } label: {
                        Label("Share downloaded file…", systemImage: "doc")
                    }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                startDownload(video)
            } label: {
                downloadButtonLabel(for: video)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isDownloadActive(for: video) || downloads.localFile(for: video.id) != nil)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func downloadButtonLabel(for video: Video) -> some View {
        if downloads.localFile(for: video.id) != nil {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
        } else if isDownloadActive(for: video) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading")
            }
        } else {
            Label("Download", systemImage: "arrow.down.circle")
        }
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

    private func watchURL(_ video: Video) -> URL? {
        URL(string: "https://www.youtube.com/watch?v=\(video.id)")
    }

    /// `youtu.be/<id>?t=<seconds>` is the canonical share-with-timestamp URL YouTube understands.
    private func watchURLAtCurrentTime(_ video: Video) -> URL? {
        let seconds = Int(player.elapsed)
        return URL(string: "https://youtu.be/\(video.id)?t=\(seconds)")
            ?? URL(string: "https://youtu.be/\(video.id)")
    }

    // MARK: - Queue controls

    /// Compact autoplay control kept beside the Up Next heading so it remains visible while the
    /// queue is collapsed. The filled glyph is the on state.
    @ViewBuilder
    private var autoplayButton: some View {
        Button {
            autoplayNext.toggle()
        } label: {
            Image(systemName: autoplayNext ? "play.circle.fill" : "play.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Autoplay next")
        .accessibilityValue(autoplayNext ? "On" : "Off")
    }

    /// Repeat pill — cycles through .off → .all → .one → .off. Active states (.all and .one) get
    /// the capsule highlight; `.one` swaps to the `repeat.1` SF Symbol so the user can see the
    /// single-track variant at a glance.
    @ViewBuilder
    private var repeatButton: some View {
        Button {
            switch player.queue.repeatMode {
            case .off: player.queue.repeatMode = .all
            case .all: player.queue.repeatMode = .one
            case .one: player.queue.repeatMode = .off
            }
        } label: {
            Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 28)
                .background {
                    if player.queue.repeatMode != .off {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Queue panel sizing

    /// Fixed height of one queue row's content area. 56pt accommodates the 80×45 thumbnail with
    /// a hair of breathing room. Combined with our `.listRowInsets(top: 4, bottom: 4)` each row
    /// occupies 64pt of vertical space in the List.
    private static let queueRowHeight: CGFloat = 56

    /// Per-row footprint including insets, used by `queueListHeight` below.
    private static let queueRowFootprint: CGFloat = queueRowHeight + 8 // 4pt top + 4pt bottom insets

    /// Total height we hand to the queue `List`. Sized for the actual number of items + a 32pt
    /// bottom margin so the last row's edit-handle / swipe affordance isn't truncated.
    private var queueListHeight: CGFloat {
        let count = max(1, displayedQueueIndices.count)
        return CGFloat(count) * Self.queueRowFootprint + 32
    }

    private var displayedQueueIndices: [Int] {
        player.queue.items.indices.filter { player.queue.items[$0].id != player.currentVideo?.id }
    }

    // MARK: - Queue panel

    @ViewBuilder
    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    isQueueExpanded.toggle()
                } label: {
                    HStack {
                        SectionHeader(title: "Up next")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if isQueueExpanded {
                    autoplayButton
                    repeatButton
                }
                Button {
                    isQueueExpanded.toggle()
                } label: {
                    Image(systemName: isQueueExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            // `List` is the cleanest source of drag-to-reorder + swipe-to-delete in SwiftUI. We're
            // already inside a ScrollView, so we cap the list with a generous fixed height so it
            // doesn't try to consume the outer scroll's gesture space.
            if isQueueExpanded {
                List {
                    ForEach(displayedQueueIndices, id: \.self) { queueIndex in
                        queueRow(player.queue.items[queueIndex])
                            .listRowBackground(Color.clear)
                            .frame(height: Self.queueRowHeight)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { offsets in
                        let queueIndices = offsets.compactMap { displayIndex in
                            displayedQueueIndices.indices.contains(displayIndex)
                                ? displayedQueueIndices[displayIndex]
                                : nil
                        }
                        for queueIndex in queueIndices.sorted(by: >) {
                            player.queue.remove(at: queueIndex)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: queueListHeight)
            }
        }
        .onChange(of: player.currentVideo?.id) {
            isQueueExpanded = false
        }
    }

    @ViewBuilder
    private func queueRow(_ video: Video) -> some View {
        HStack(spacing: 0) {
            Button {
                player.load(video)
            } label: {
                HStack(spacing: 12) {
                    // Thumbnail with duration badge in the bottom-right corner — same affordance
                    // YouTube uses on its own video tiles. Costs no extra row height.
                    ZStack(alignment: .bottomTrailing) {
                        KFImage(video.thumbnailURL)
                            .thumbnail(size: CGSize(width: 80, height: 45)) {
                                Color.gray.opacity(0.2)
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 45)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if !video.durationString.isEmpty {
                            Text(video.durationString)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                                .padding(3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(.subheadline)
                            .lineLimit(2)
                        // Channel name + playback count joined by a middle dot. Either piece can be
                        // empty (older listings sometimes omit view count), filter before joining so
                        // there are no stray separators.
                        Text(queueRowMetadata(for: video))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if video.id == player.currentVideo?.id {
                        // Animated audio bars instead of the static speaker glyph. Animates only
                        // for the matched row; other rows render nothing because the parent `if`
                        // gates mounting.
                        NowPlayingIndicator(videoID: video.id)
                    }
                }
            }
            .buttonStyle(.plain)

            // Sibling of the load-button so taps land in the Menu instead of the row's
            // play handler. Same actions as the row would get in search/history/library.
            VideoMoreActionsMenu(video: video)
        }
    }

    /// "Channel • 1.2M views" for the queue row's second line. Drops the dot if either side is
    /// missing so we never render a dangling separator.
    private func queueRowMetadata(for video: Video) -> String {
        [video.channelName, video.viewCountString]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
