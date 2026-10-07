import SwiftUI
import UIKit

/// Top-level tabbed shell. The in-app floating player persists across tabs.
///
/// Tab layout: Feed, Library, Downloads, and Search (a separate system button on iOS 26).
/// - Feed (latest cached videos from local subscriptions)
/// - Library (device-local history, subscriptions, and playlists)
/// - Downloads (saved videos and transfer queue)
/// - Search (search field, suggestions, results, and local recent searches)
/// Settings opens from Library's toolbar.
@available(iOS 17.0, *)
struct RootView: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(AppVisitState.self) private var appVisitState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: Tab
    @AppStorage("showSubscriptionFeedTab") private var showSubscriptionFeedTab = true
    @AppStorage("appFontPreset") private var appFontPresetRaw = AppFontPreset.system.rawValue
    @State private var navigationRouter = AppNavigationRouter()
    private enum RootSheet: String, Identifiable {
        case settings
        case subscriptionGroups

        var id: String { rawValue }
    }

    @State private var rootSheet: RootSheet?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    enum Tab: String, Hashable {
        case feed, search, library, downloads
    }

    private var queueNoticeBottomPadding: CGFloat {
        if player.fullScreenPresented {
            return PlayerLayoutMetrics.safeAreaInsets.bottom + 12
        }
        let miniPlayerClearance: CGFloat = player.miniPlayerVisible
            ? player.floatingMiniPlayerWidth * 9 / 16 + 26 : 8
        return PlayerLayoutMetrics.bottomTabBarClearance + miniPlayerClearance
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
        .sheet(item: $rootSheet, onDismiss: {
            log.info("Root sheet dismissed")
            rootSheet = nil
        }) { sheet in
            switch sheet {
            case .settings:
                SettingsScreen {
                    rootSheet = nil
                }
                    .presentationDragIndicator(.hidden)
            case .subscriptionGroups:
                SubscriptionGroupsScreen()
                    .presentationDragIndicator(.visible)
            }
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
                selectedTab = tab == .feed && !showSubscriptionFeedTab ? .search : tab
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
            if !showSubscriptionFeedTab, selectedTab == .feed {
                selectedTab = .search
            }
        }
        .onChange(of: showSubscriptionFeedTab) { _, isVisible in
            if !isVisible, selectedTab == .feed {
                selectedTab = .search
            }
        }
        .onChange(of: selectedTab) { previous, tab in
            log.info("Tab changed: \(previous.rawValue, privacy: .public) → \(tab.rawValue, privacy: .public)")
        }
        .environment(\.appFontPreset, AppFontPreset(rawValue: appFontPresetRaw) ?? .system)
    }

    private var tabShell: some View {
        RootTabShell(
            selection: $selectedTab,
            showsFeed: showSubscriptionFeedTab
        )
        .environment(navigationRouter)
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

}
