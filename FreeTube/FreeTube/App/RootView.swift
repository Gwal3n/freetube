import SwiftUI
import Kingfisher
import UIKit

/// Top-level tabbed shell. CLAUDE.md §8: mini-player sits above the tab bar and persists across tabs.
///
/// Tab layout: Feed, Library, Downloads, and Search (a separate system button on iOS 26).
/// - Feed (latest cached videos from local subscriptions)
/// - Library (device-local history, subscriptions, and playlists)
/// - Downloads (saved videos, transfer queue, and yt-dlp link downloads)
/// - Search (search field, suggestions, results, and local recent searches)
/// Settings opens from Library's toolbar.
@available(iOS 17.0, *)
struct RootView: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tabState = RootTabSelection()
    @State private var libraryHasBeenSelected = false
    @State private var searchActivation = 0
    @AppStorage("showSubscriptionFeedTab") private var showSubscriptionFeedTab = true
    @State private var feedNavigationRequest: AppNavigationRequest?
    @State private var searchNavigationRequest: AppNavigationRequest?
    @State private var libraryNavigationRequest: AppNavigationRequest?
    @State private var downloadsNavigationRequest: AppNavigationRequest?
    private enum RootSheet: String, Identifiable {
        case settings

        var id: String { rawValue }
    }

    @State private var rootSheet: RootSheet?
    /// Cached thumbnail for the current video so the mini-player bar shows the actual preview instead
    /// of a placeholder icon. Loaded via Kingfisher's cache when `currentVideo` changes.
    @State private var thumbnail: UIImage?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    enum Tab: String, Hashable {
        case feed, search, library, downloads
    }

    private var selectedTab: Tab {
        tabState.selected
    }

    private var queueNoticeBottomPadding: CGFloat {
        if player.fullScreenPresented {
            return PlayerLayoutMetrics.safeAreaInsets.bottom + 12
        }
        let miniPlayerClearance: CGFloat = player.miniPlayerVisible ? 68 : 8
        return PlayerLayoutMetrics.bottomTabBarClearance + miniPlayerClearance
    }

    var body: some View {
        SwiftUIPlayerContainer(thumbnail: thumbnail) {
            tabShell
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
        .sheet(item: $rootSheet, onDismiss: {
            log.info("Root sheet dismissed")
        }) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen()
                    .presentationDragIndicator(.hidden)
            }
        }
        // Refresh the cached thumbnail whenever the user picks a new video so the SwiftUI
        // mini-player can show the actual preview.
        .onChange(of: player.currentVideo?.id, initial: true) {
            loadThumbnailForCurrentVideo()
        }
        // Force light status-bar glyphs while the dark expanded player is visible, then restore
        // the app's normal appearance when it returns to the mini-player.
        .onChange(of: player.fullScreenPresented) { _, presented in
            log.info("Player expanded presentation changed: \(presented)")
            updateStatusBarOverride(forFullScreenOpen: presented)
            if presented {
                player.requestInlinePlaybackRestoration()
            }
        }
        .onChange(of: player.miniPlayerVisible) { _, visible in
            log.info("Player mini presentation changed: \(visible)")
        }
        .onChange(of: scenePhase) { _, phase in
            log.info("Scene phase changed: \(String(describing: phase))")
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
                if tab == .library { activateLibrary() }
                tabState.select(tab, showsFeed: showSubscriptionFeedTab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenSettings)) { _ in
            log.info("Root-owned Settings requested")
            rootSheet = .settings
        }
        .onChange(of: rootSheet) { previous, current in
            log.info("Root sheet binding: \(previous?.rawValue ?? "none") → \(current?.rawValue ?? "none")")
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
            tabState.start(showsFeed: showSubscriptionFeedTab)
        }
        .onChange(of: showSubscriptionFeedTab) { _, isVisible in
            tabState.updateFeedVisibility(isVisible)
        }
        .onChange(of: tabState.selected) { previous, tab in
            log.info("Tab changed: \(previous.rawValue, privacy: .public) → \(tab.rawValue, privacy: .public)")
        }
    }

    private var tabShell: some View {
        RootTabShell(
            selection: tabSelection,
            showsFeed: showSubscriptionFeedTab,
            searchActivation: searchActivation,
            feedNavigationRequest: feedNavigationRequest,
            libraryNavigationRequest: libraryNavigationRequest,
            libraryHasBeenSelected: libraryHasBeenSelected,
            downloadsNavigationRequest: downloadsNavigationRequest,
            searchNavigationRequest: searchNavigationRequest
        )
    }

    /// Re-selecting Search requests focus without a gesture recognizer on the native tab bar.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .library { activateLibrary() }
                if newTab == .feed, !showSubscriptionFeedTab {
                    tabState.select(.search, showsFeed: false)
                    return
                }
                if newTab == .search, selectedTab == .search {
                    searchActivation &+= 1
                }
                tabState.select(newTab, showsFeed: showSubscriptionFeedTab)
            }
        )
    }

    private func activateLibrary() {
        guard !libraryHasBeenSelected else { return }
        libraryHasBeenSelected = true
        log.info("Library first selection: mounting navigation stack")
    }

    /// Open player/context-menu links in the current tab's existing navigation stack. Ordinary
    /// minimization and system alerts never select a tab or create navigation requests.
    private func routeFromPlayer(_ destination: AppNavigationRequest.Destination) {
        let request = AppNavigationRequest(destination: destination)
        switch selectedTab {
        case .feed:
            feedNavigationRequest = request
        case .search:
            searchNavigationRequest = request
        case .library:
            libraryNavigationRequest = request
        case .downloads:
            downloadsNavigationRequest = request
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
