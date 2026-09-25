import SwiftUI
import Kingfisher
import UIKit

/// Top-level tabbed shell.
///
/// Three peer tabs — Feed, Library, Downloads — plus Search in the dedicated search role, which
/// the system detaches into its own button beside the bar. The mini player is the app's own
/// overlay, sitting above the tab bar. Settings lives in Library's toolbar.
struct RootView: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // A system picker temporarily deactivates and may reconstruct the tab hierarchy. Scene-backed
    // selection prevents that lifecycle boundary from snapping the app back to Feed.
    @SceneStorage("selectedRootTab") private var selectedTabRaw = Tab.feed.rawValue
    @State private var searchActivation = 0
    @AppStorage("showSubscriptionFeedTab") private var showSubscriptionFeedTab = true
    @State private var feedNavigationRequest: AppNavigationRequest?
    @State private var searchNavigationRequest: AppNavigationRequest?
    @State private var libraryNavigationRequest: AppNavigationRequest?
    @State private var downloadsNavigationRequest: AppNavigationRequest?
    /// Monotonic counter rather than a Bool: the Settings sheet lives in Library, and a repeated
    /// ⌘, must reopen it even if the flag was never reset.
    @State private var settingsRequest = 0
    /// Direct observation of the shared download manager — no AsyncStream subscription needed since
    /// `DownloadManager` is itself `@Observable`. Both this view (for the badge) and `DownloadsScreen`
    /// (for the list) read the same source of truth.
    @State private var downloads = DownloadManager.shared
    /// Cached thumbnail for the current video so the mini-player bar shows the actual preview instead
    /// of a placeholder icon. Loaded via Kingfisher's cache when `currentVideo` changes.
    @State private var thumbnail: UIImage?

    enum Tab: String, Hashable {
        case feed, search, library, downloads
    }

    private var selectedTab: Tab {
        Tab(rawValue: selectedTabRaw) ?? .feed
    }

    private var activeDownloadsCount: Int {
        downloads.activeTasks.filter { snapshot in
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }.count
    }

    /// Lifts the transient queue toast clear of the tab bar and, when playback is collapsed, the
    /// mini player sitting on top of it.
    private var queueNoticeBottomPadding: CGFloat {
        if player.fullScreenPresented {
            return PlayerLayoutMetrics.safeAreaInsets.bottom + 12
        }
        let miniPlayerClearance: CGFloat = player.miniPlayerVisible ? 68 : 8
        return PlayerLayoutMetrics.bottomTabBarClearance + miniPlayerClearance
    }

    var body: some View {
        tabShell
        .allowsHitTesting(!player.fullScreenPresented)
        .overlay {
            // Host the custom player above the native TabView, independently of
            // whichever tab is currently selected. An overlay does not contribute
            // to the tab view's layout or change its native bar placement.
            SwiftUIPlayerContainer(thumbnail: thumbnail) {
                Color.clear.allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = player.queueNotice {
                HStack(spacing: 10) {
                    Label {
                        Text(notice.message)
                    } icon: {
                        Image(systemName: notice.offersUndo ? "arrow.uturn.backward" : "checkmark")
                    }
                    if notice.offersUndo {
                        Divider()
                            .frame(height: 18)
                        Button("Undo") {
                            player.undoQueueNotice()
                        }
                        .fontWeight(.semibold)
                        .buttonStyle(.plain)
                    }
                }
                .lineLimit(1)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .fixedSize(horizontal: true, vertical: false)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                .padding(.bottom, queueNoticeBottomPadding)
                .allowsHitTesting(notice.offersUndo)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : InterfaceMotion.notice, value: player.queueNotice?.id)
        // Refresh the cached thumbnail whenever the user picks a new video so the SwiftUI
        // mini-player can show the actual preview.
        .onChange(of: player.currentVideo?.id, initial: true) {
            loadThumbnailForCurrentVideo()
        }
        .onChange(of: player.fullScreenPresented) { _, presented in
            updateStatusBarOverride(forFullScreenOpen: presented)
            if presented {
                player.requestInlinePlaybackRestoration()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Reopening the app from an automatic PiP session may leave the popup binding true,
            // so there is no false→true popup transition to observe. Foreground activation is
            // the second explicit signal that the same video should return inline.
            if phase == .active, player.fullScreenPresented {
                player.requestInlinePlaybackRestoration()
            }
        }
        // Menu-bar / keyboard-shortcut driven tab switching from `MacCommands`. The
        // notification is meaningful only on Mac (where the menu bar exists) and on iPad
        // with a hardware keyboard; everywhere else nobody posts it and this is a no-op.
        .onReceive(NotificationCenter.default.publisher(for: .freetubeSelectTab)) { note in
            if let tab = note.object as? Tab {
                selectedTabRaw = tab.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenSettings)) { _ in
            selectedTabRaw = Tab.library.rawValue
            settingsRequest &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenChannel)) { note in
            guard let channelID = note.object as? String, !channelID.isEmpty else { return }
            routeFromPlayer(.channel(channelID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenPlaylist)) { note in
            guard let playlistID = note.object as? String, !playlistID.isEmpty else { return }
            routeFromPlayer(.playlist(playlistID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenLocalPlaylist)) { note in
            guard let playlistID = note.object as? String, !playlistID.isEmpty else { return }
            routeFromPlayer(.localPlaylist(playlistID))
        }
        .onAppear {
            if !showSubscriptionFeedTab, selectedTab == .feed {
                selectedTabRaw = Tab.search.rawValue
            }
        }
        .onChange(of: showSubscriptionFeedTab) { _, isVisible in
            if !isVisible, selectedTab == .feed {
                selectedTabRaw = Tab.search.rawValue
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: tabSelection) {
            if showSubscriptionFeedTab {
                SwiftUI.Tab("Feed", systemImage: "rectangle.stack", value: Tab.feed) {
                    SubscriptionFeedScreen(navigationRequest: feedNavigationRequest)
                }
            }

            SwiftUI.Tab("Library", systemImage: "play.square.stack", value: Tab.library) {
                LibraryScreen(
                    navigationRequest: libraryNavigationRequest,
                    settingsRequest: settingsRequest
                )
            }

            SwiftUI.Tab("Downloads", systemImage: "arrow.down.circle", value: Tab.downloads) {
                DownloadsScreen(navigationRequest: downloadsNavigationRequest)
            }
            .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)

            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                HomeScreen(searchActivation: searchActivation, navigationRequest: searchNavigationRequest)
            }
        }
    }

    /// SwiftUI writes the selection binding even when an already-selected tab is tapped, which is
    /// how re-selecting Search re-focuses the field without a gesture recognizer on the tab bar.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .feed, !showSubscriptionFeedTab {
                    selectedTabRaw = Tab.search.rawValue
                    return
                }
                if newTab == .search, selectedTab == .search {
                    searchActivation &+= 1
                }
                selectedTabRaw = newTab.rawValue
            }
        )
    }

    /// Player metadata is global, so its links need one stable navigation owner rather than being
    /// handed to whichever unrelated tab happens to be visible. Feed is the app's browsing root;
    /// Search is the fallback when the user hides Feed. Deliver the request on the next main-actor
    /// turn so a lazily created tab observes a change instead of mounting with an already-set value.
    private func routeFromPlayer(_ destination: AppNavigationRequest.Destination) {
        let request = AppNavigationRequest(destination: destination)
        let destinationTab: Tab = showSubscriptionFeedTab ? .feed : .search
        selectedTabRaw = destinationTab.rawValue
        Task { @MainActor in
            await Task.yield()
            switch destinationTab {
            case .feed:
                feedNavigationRequest = request
            case .search:
                searchNavigationRequest = request
            case .library, .downloads:
                break
            }
        }
    }

    private func updateStatusBarOverride(forFullScreenOpen open: Bool) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        window?.overrideUserInterfaceStyle = open ? .dark : .unspecified
    }

    /// Refreshes `thumbnail` whenever the current video changes. Tries three sources in order:
    ///  1. Kingfisher's in-memory cache for the video's `thumbnailURL` (synchronous → no flash).
    ///  2. `DownloadsStore`'s xattr-stored compressed thumbnail (for videos played from the Downloads tab,
    ///     where the `Video` object the screen built has `thumbnailURL == nil`).
    ///  3. Async Kingfisher fetch from disk/network if neither of the above hit.
    /// Clears `thumbnail` immediately first so we don't show the previous video's preview while
    /// the new one is loading.
    private func loadThumbnailForCurrentVideo() {
        thumbnail = nil

        guard let video = player.currentVideo else { return }

        // 1. Synchronous in-memory cache for the thumbnail URL.
        if let url = video.thumbnailURL,
           let cached = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey) {
            thumbnail = cached
            return
        }

        // 2. Xattr-stored thumbnail for downloaded videos. `DownloadsStore` keeps the
        // current snapshot in memory, so the lookup is synchronous and the compressed JPEG
        // bytes decode straight to a `UIImage`.
        let videoID = video.id
        if let data = DownloadsStore.shared.thumbnail(forVideoID: videoID),
           let image = UIImage(data: data) {
            self.thumbnail = image
            return
        }

        // 3. Async network/disk-cache fetch (in parallel with the xattr lookup above —
        // whichever completes first and matches the current video wins).
        guard let url = video.thumbnailURL else { return }
        KingfisherManager.shared.retrieveImage(with: url) { [videoID = video.id] result in
            guard case .success(let value) = result else { return }
            Task { @MainActor in
                // Guard against a race: if the user has already switched to another video while
                // this fetch was inflight, don't stomp the new thumbnail with the stale one.
                guard self.player.currentVideo?.id == videoID else { return }
                self.thumbnail = value.image
            }
        }
    }

}
