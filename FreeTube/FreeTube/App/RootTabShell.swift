import SwiftUI

@available(iOS 17.0, *)
struct RootTabShell: View {
    @Binding var selection: RootView.Tab
    /// Incognito can hide Feed/Library even when their tab toggles stay on.
    let hideFeedForIncognito: Bool
    let hideLibraryForIncognito: Bool

    @AppStorage("tabBarOrder") private var tabBarOrderRaw = TabBarOrder.defaultValue
    @AppStorage("showTabBarLabels") private var showTabBarLabels = true
    @AppStorage("showSubscriptionFeedTab") private var showFeedTab = true
    @AppStorage("showLibraryTab") private var showLibraryTab = true
    @AppStorage("showDownloadsTab") private var showDownloadsTab = true
    @AppStorage("showSearchTab") private var showSearchTab = true
    @AppStorage("showSettingsTab") private var showSettingsTab = false
    @AppStorage("useAccentTheme") private var useAccentTheme = false
    @AppStorage("accentNavigationOnly") private var accentNavigationOnly = false
    @AppStorage("appAccentPreset") private var appAccentPresetRaw = AppAccentPreset.classic.rawValue
    @AppStorage("appCustomAccentHex") private var appCustomAccentHex = "#FF3B30"

    private var tabTint: Color {
        useAccentTheme
            ? (AppAccentPreset(rawValue: appAccentPresetRaw) ?? .classic).color(customHex: appCustomAccentHex)
            : .primary
    }

    private let downloads = DownloadManager.shared

    private var activeDownloadsCount: Int {
        downloads.activeTasks.filter { snapshot in
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }.count
    }

    private var showsFeed: Bool { showFeedTab && !hideFeedForIncognito }
    private var showsLibrary: Bool { showLibraryTab && !hideLibraryForIncognito }
    private var showsSearch: Bool { showSearchTab }

    private var visibleTabs: [RootView.Tab] {
        TabBarOrder.visibleTabs(
            from: tabBarOrderRaw,
            feed: showsFeed,
            library: showsLibrary,
            downloads: showDownloadsTab,
            search: showsSearch,
            settings: showSettingsTab
        )
    }

    private var visibleOrdinaryTabs: [RootView.Tab] {
        visibleTabs.filter { $0 != .search }
    }

    /// TabView caches its structure; remount when visibility or order changes so Settings edits apply without relaunch.
    private var tabShellIdentity: String {
        let ordered = visibleOrdinaryTabs.map(\.rawValue).joined(separator: ",")
        return "\(ordered)|search:\(showsSearch)|labels:\(showTabBarLabels)"
    }

    @ViewBuilder
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $selection) {
                    ForEach(visibleOrdinaryTabs, id: \.self) { tab in
                        SwiftUI.Tab(value: tab) {
                            screen(for: tab)
                        } label: {
                            if showTabBarLabels {
                                Label(tab.title, systemImage: tab.symbol)
                            } else {
                                Image(systemName: tab.symbol)
                                    .accessibilityLabel(Text(tab.title))
                            }
                        }
                        .badge(tab == .downloads && activeDownloadsCount > 0 ? activeDownloadsCount : 0)
                    }
                    if showsSearch {
                        SwiftUI.Tab(value: RootView.Tab.search, role: .search) {
                            screen(for: .search)
                        } label: {
                            if showTabBarLabels {
                                Label("Search", systemImage: "magnifyingglass")
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .accessibilityLabel("Search")
                            }
                        }
                    }
                }
                .tint(tabTint)
            } else {
                legacyTabShell
                    .tint(tabTint)
            }
        }
        .id(tabShellIdentity)
        .onChange(of: tabShellIdentity) { _, _ in
            selectVisibleTabIfNeeded()
        }
        .onAppear {
            selectVisibleTabIfNeeded()
        }
    }

    /// iOS 17–25 compatibility. iOS 26 uses the modern `Tab` declarations above for its
    private var legacyTabShell: some View {
        TabView(selection: $selection) {
            ForEach(visibleOrdinaryTabs, id: \.self) { tab in
                screen(for: tab)
                    .tabItem {
                        if showTabBarLabels {
                            Label(tab.title, systemImage: tab.symbol)
                        } else {
                            Image(systemName: tab.symbol)
                                .accessibilityLabel(Text(tab.title))
                        }
                    }
                    .badge(tab == .downloads && activeDownloadsCount > 0 ? activeDownloadsCount : 0)
                    .tag(tab)
            }
            if showsSearch {
                screen(for: .search)
                    .tabItem {
                        if showTabBarLabels {
                            Label("Search", systemImage: "magnifyingglass")
                        } else {
                            Image(systemName: "magnifyingglass")
                                .accessibilityLabel("Search")
                        }
                    }
                    .tag(RootView.Tab.search)
            }
        }
    }

    private func selectVisibleTabIfNeeded() {
        guard !visibleTabs.contains(selection) else { return }
        selection = visibleTabs.first ?? .search
    }

    @ViewBuilder
    private func screen(for tab: RootView.Tab) -> some View {
        Group {
            switch tab {
            case .feed:
                SubscriptionFeedScreen(selectedTab: $selection)
            case .library:
                NavigationStack { LibraryScreen() }
            case .downloads:
                DownloadsScreen()
            case .search:
                HomeScreen()
            case .settings:
                SettingsScreen(onClose: nil)
            }
        }
        .tint(useAccentTheme && accentNavigationOnly ? .primary : tabTint)
        .overlay {
            if tab == selection {
                FloatingPlayerUnderlay()
            }
        }
    }

}
