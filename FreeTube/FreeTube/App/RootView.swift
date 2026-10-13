import SwiftUI

/// Top-level tabbed shell. The in-app floating player persists across tabs.
///
/// Tab layout is customizable; Search keeps its native system role on iOS 26.
/// - Feed (latest cached videos from local subscriptions)
/// - Library (device-local history, subscriptions, and playlists)
/// - Downloads (saved videos and transfer queue)
/// - Search (search field, suggestions, results, and local recent searches)
/// Settings opens from Library's toolbar or an optional dedicated tab.
@available(iOS 17.0, *)
struct RootView: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(AppVisitState.self) private var appVisitState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: Tab
    @AppStorage("showSubscriptionFeedTab") private var showSubscriptionFeedTab = true
    @AppStorage("showLibraryTab") private var showLibraryTab = true
    @AppStorage("showDownloadsTab") private var showDownloadsTab = true
    @AppStorage("showSearchTab") private var showSearchTab = true
    @AppStorage("showSettingsTab") private var showSettingsTab = false
    @AppStorage("tabBarOrder") private var tabBarOrderRaw = TabBarOrder.defaultValue
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("incognitoHideFeed") private var incognitoHideFeed = false
    @AppStorage("incognitoHideLibrary") private var incognitoHideLibrary = false
    @AppStorage("appFontPreset") private var appFontPresetRaw = AppFontPreset.system.rawValue
    @State private var navigationRouter = AppNavigationRouter()
    @State private var incomingLinkModel = IncomingLinkViewModel()
    @State private var errorPresenter = AppErrorPresenter()
    private enum RootSheet: String, Identifiable {
        case settings
        case subscriptionGroups

        var id: String { rawValue }
    }

    @State private var rootSheet: RootSheet?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    enum Tab: String, Hashable {
        case feed, search, library, downloads, settings

        var title: LocalizedStringKey {
            switch self {
            case .feed: "Feed"
            case .search: "Search"
            case .library: "Library"
            case .downloads: "Downloads"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .feed: "rectangle.stack"
            case .search: "magnifyingglass"
            case .library: "play.square.stack"
            case .downloads: "arrow.down.circle"
            case .settings: "gearshape"
            }
        }
    }

    private var showsFeed: Bool {
        showSubscriptionFeedTab && !(incognitoEnabled && incognitoHideFeed)
    }

    private var showsLibrary: Bool {
        showLibraryTab && !(incognitoEnabled && incognitoHideLibrary)
    }

    private var visibleTabs: [Tab] {
        TabBarOrder.visibleTabs(
            from: tabBarOrderRaw,
            feed: showsFeed,
            library: showsLibrary,
            downloads: showDownloadsTab,
            search: showSearchTab,
            settings: showSettingsTab
        )
    }

    private var queueNoticeBottomPadding: CGFloat {
        if player.fullScreenPresented {
            return PlayerLayoutMetrics.safeAreaInsets.bottom + 12
        }
        let miniPlayerClearance: CGFloat = player.miniPlayerVisible
            ? player.floatingMiniPlayerWidth * 9 / 16 + 26 : 8
        return PlayerLayoutMetrics.bottomTabBarClearance + miniPlayerClearance
    }

    private var errorToastBottomClearance: CGFloat {
        queueNoticeBottomPadding + (player.queueNotice == nil ? 0 : MediaStyle.actionSize + 8)
    }

    var body: some View {
        SwiftUIPlayerContainer {
            tabShell
        }
        .overlay(alignment: .bottom) {
            if let notice = player.queueNotice {
                TransientNoticePill(
                    title: Text(notice.message),
                    systemImage: notice.offersUndo ? "arrow.uturn.backward" : "checkmark",
                    onUndo: notice.offersUndo ? { player.undoQueueNotice() } : nil
                )
                .padding(.bottom, queueNoticeBottomPadding)
                .allowsHitTesting(notice.offersUndo)
            }
        }
        .animation(reduceMotion ? nil : InterfaceMotion.notice, value: player.queueNotice?.id)
        .errorToast(
            Bindable(errorPresenter).errorState,
            bottomClearance: errorToastBottomClearance
        )
        .onOpenURL { url in
            Task { await openIncomingLink(url) }
        }
        .sheet(item: $rootSheet, onDismiss: {
            log.info("Root sheet dismissed")
            rootSheet = nil
        }) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen(onClose: {
                    rootSheet = nil
                })
                    .environment(navigationRouter)
                    .presentationDragIndicator(.hidden)
            case .subscriptionGroups:
                SubscriptionGroupsScreen()
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: player.fullScreenPresented) { _, presented in
            log.info("Player expanded presentation changed: \(presented)")
            if presented {
                player.requestInlinePlaybackRestoration()
            }
        }
        .onChange(of: player.miniPlayerVisible) { _, visible in
            log.info("Player mini presentation changed: \(visible)")
        }
        .onChange(of: scenePhase) { _, phase in
            log.info("Scene phase changed: \(String(describing: phase))")
            appVisitState.scenePhaseChanged(phase)
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
                selectedTab = visibleTabs.contains(tab) ? tab : visibleTabs[0]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenSettings)) { _ in
            log.info("Root-owned Settings requested")
            rootSheet = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenSubscriptionGroups)) { _ in
            rootSheet = .subscriptionGroups
        }
        .onChange(of: rootSheet) { previous, current in
            log.info("Root sheet binding: \(previous?.rawValue ?? "none") → \(current?.rawValue ?? "none")")
        }
        .onReceive(NotificationCenter.default.publisher(for: .freetubeOpenChannel)) { note in
            guard let channelID = note.object as? String, !channelID.isEmpty else { return }
            log.info("Root received player channel navigation on tab=\(selectedTab.rawValue)")
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
            log.info("Root appeared with tab=\(selectedTab.rawValue, privacy: .public)")
            selectVisibleTabIfNeeded()
        }
        .onChange(of: showsFeed) { _, _ in
            selectVisibleTabIfNeeded()
        }
        .onChange(of: showsLibrary) { _, _ in
            selectVisibleTabIfNeeded()
        }
        .onChange(of: showDownloadsTab) { _, _ in selectVisibleTabIfNeeded() }
        .onChange(of: showSearchTab) { _, _ in selectVisibleTabIfNeeded() }
        .onChange(of: showSettingsTab) { _, _ in selectVisibleTabIfNeeded() }
        .onChange(of: selectedTab) { previous, tab in
            log.info("Tab changed: \(previous.rawValue, privacy: .public) → \(tab.rawValue, privacy: .public)")
        }
        .environment(\.appFontPreset, AppFontPreset(rawValue: appFontPresetRaw) ?? .system)
        .environment(navigationRouter)
        .environment(errorPresenter)
    }

    private var tabShell: some View {
        RootTabShell(
            selection: $selectedTab,
            showsFeed: showsFeed,
            showsLibrary: showsLibrary,
            showsDownloads: showDownloadsTab,
            showsSearch: showSearchTab,
            showsSettings: showSettingsTab
        )
    }

    private func selectVisibleTabIfNeeded() {
        if !visibleTabs.contains(selectedTab) {
            selectedTab = visibleTabs[0]
        }
    }

    /// Open player/context-menu links in the current tab's existing navigation stack. Ordinary
    /// minimization and system alerts never select a tab or create navigation requests.
    private func routeFromPlayer(_ destination: AppNavigationRequest.Destination) {
        let request = AppNavigationRequest(destination: destination)
        log.info("Root routing player destination to tab=\(selectedTab.rawValue)")
        switch selectedTab {
        case .feed:
            navigationRouter.feed = request
        case .search:
            navigationRouter.search = request
        case .library:
            navigationRouter.library = request
        case .downloads:
            navigationRouter.downloads = request
        case .settings:
            navigationRouter.settings = request
        }
    }

    /// Handle external public links without changing the selected tab. The tab's existing
    /// navigation stack receives channel/playlist destinations; video resolution starts first.
    private func openIncomingLink(_ url: URL) async {
        guard let link = YouTubeIncomingLink.parse(url) else {
            errorPresenter.present(ErrorState(message: "This isn't a supported YouTube link."))
            return
        }
        switch link {
        case .video(let id):
            player.load(YouTubeVideoLink.playbackSeed(for: id))
            await Task.yield()
            if let metadata = await incomingLinkModel.metadata(for: id) {
                player.enrichCurrentVideo(with: metadata)
            }
        case .channel(let id):
            routeFromPlayer(.channel(id))
        case .channelHandle(let handle):
            guard let id = await incomingLinkModel.channelID(for: handle) else {
                errorPresenter.present(ErrorState(
                    message: "This channel couldn't be opened. Try searching for it instead."
                ))
                return
            }
            routeFromPlayer(.channel(id))
        case .playlist(let id):
            routeFromPlayer(.playlist(id))
        }
    }
}
