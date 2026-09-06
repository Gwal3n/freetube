import SwiftUI
import Kingfisher
import UIKit

/// Top-level tabbed shell. CLAUDE.md §8: mini-player sits above the tab bar and persists across tabs.
///
/// Tab layout (5):
/// - Feed (latest cached videos from local subscriptions)
/// - Search (search field, suggestions, results, and local recent searches)
/// - Library (subsumes the former Account + Subscriptions tabs; includes Favorites/Recents/Playlists/Login)
/// - Downloads (saved videos, transfer queue, and yt-dlp link downloads)
/// - Settings (preferences, quality, reset-session)
@available(iOS 17.0, *)
struct RootView: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .feed
    @State private var searchActivation = 0
    @AppStorage("showSubscriptionFeedTab") private var showSubscriptionFeedTab = true
    @State private var feedNavigationRequest: AppNavigationRequest?
    @State private var searchNavigationRequest: AppNavigationRequest?
    @State private var libraryNavigationRequest: AppNavigationRequest?
    @State private var downloadsNavigationRequest: AppNavigationRequest?
    /// Direct observation of the shared download manager — no AsyncStream subscription needed since
    /// `DownloadManager` is itself `@Observable`. Both this view (for the badge) and `DownloadsScreen`
    /// (for the list) read the same source of truth.
    @State private var downloads = DownloadManager.shared
    /// Cached thumbnail for the current video so the mini-player bar shows the actual preview instead
    /// of a placeholder icon. Loaded via Kingfisher's cache when `currentVideo` changes.
    @State private var thumbnail: UIImage?

    enum Tab: Hashable {
        case feed, search, library, downloads, settings
    }

    private var activeDownloadsCount: Int {
        downloads.activeTasks.filter { snapshot in
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }.count
    }

    var body: some View {
        SwiftUIPlayerContainer(thumbnail: thumbnail) {
            tabShell
        }
        .overlay(alignment: .top) {
            if let notice = player.queueNotice {
                Label {
                    Text("Playing next: \(notice.title)")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "text.insert")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                .padding(.top, 8)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24), value: player.queueNotice?.id)
        .task {
            await SessionManager.shared.bootstrap()
        }
        // Refresh the cached thumbnail whenever the user picks a new video so the SwiftUI
        // mini-player can show the actual preview.
        .onChange(of: player.currentVideo?.id, initial: true) {
            loadThumbnailForCurrentVideo()
        }
        // Force light status-bar glyphs while the dark expanded player is visible, then restore
        // the app's normal appearance when it returns to the mini-player.
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
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenChannel)) { note in
            guard let channelID = note.object as? String, !channelID.isEmpty else { return }
            routeInSelectedTab(.channel(channelID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenPlaylist)) { note in
            guard let playlistID = note.object as? String, !playlistID.isEmpty else { return }
            routeInSelectedTab(.playlist(playlistID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenLocalPlaylist)) { note in
            guard let playlistID = note.object as? String, !playlistID.isEmpty else { return }
            routeInSelectedTab(.localPlaylist(playlistID))
        }
        .onAppear {
            if !showSubscriptionFeedTab, selectedTab == .feed { selectedTab = .search }
        }
        .onChange(of: showSubscriptionFeedTab) { _, isVisible in
            if !isVisible, selectedTab == .feed { selectedTab = .search }
        }
    }

    @ViewBuilder
    private var tabShell: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: tabSelection) {
                if showSubscriptionFeedTab {
                    SwiftUI.Tab("Feed", systemImage: "rectangle.stack", value: Tab.feed) {
                        SubscriptionFeedScreen(navigationRequest: feedNavigationRequest)
                    }
                }

                SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search) {
                    HomeScreen(searchActivation: searchActivation, navigationRequest: searchNavigationRequest)
                }

                SwiftUI.Tab("Library", systemImage: "play.square.stack", value: Tab.library) {
                    LibraryScreen(navigationRequest: libraryNavigationRequest)
                }

                SwiftUI.Tab("Downloads", systemImage: "arrow.down.circle", value: Tab.downloads) {
                    DownloadsScreen(navigationRequest: downloadsNavigationRequest)
                }
                .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)

                SwiftUI.Tab("Settings", systemImage: "gearshape.fill", value: Tab.settings) {
                    SettingsScreen()
                }
            }
        } else {
            legacyTabShell
        }
    }

    /// iOS 17–25 compatibility. iOS 26 uses the modern `Tab` declarations above for its
    /// native Liquid Glass tab bar, while Search remains an ordinary peer tab on every OS.
    private var legacyTabShell: some View {
        TabView(selection: tabSelection) {
            if showSubscriptionFeedTab {
                SubscriptionFeedScreen(navigationRequest: feedNavigationRequest)
                    .tabItem { Label("Feed", systemImage: "rectangle.stack") }
                    .tag(Tab.feed)
            }

            HomeScreen(searchActivation: searchActivation, navigationRequest: searchNavigationRequest)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            LibraryScreen(navigationRequest: libraryNavigationRequest)
                .tabItem { Label("Library", systemImage: "play.square.stack") }
                .tag(Tab.library)

            DownloadsScreen(navigationRequest: downloadsNavigationRequest)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)
                .tag(Tab.downloads)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }

    /// Keep Search as an ordinary peer tab. SwiftUI writes the selection binding even when an
    /// already-selected tab item is tapped, which lets us request search activation without the
    /// detached iOS 26 `.search` tab role or a gesture recognizer on the native tab bar.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .feed, !showSubscriptionFeedTab {
                    selectedTab = .search
                    return
                }
                if newTab == .search, selectedTab == .search {
                    searchActivation &+= 1
                }
                selectedTab = newTab
            }
        )
    }

    private func routeInSelectedTab(_ destination: AppNavigationRequest.Destination) {
        let request = AppNavigationRequest(destination: destination)
        switch selectedTab {
        case .feed: feedNavigationRequest = request
        case .search: searchNavigationRequest = request
        case .library: libraryNavigationRequest = request
        case .downloads: downloadsNavigationRequest = request
        case .settings: break
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
