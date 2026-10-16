import SwiftUI

/// A stable native tab owner independent of playback artwork, presentation, and gesture updates.
@available(iOS 17.0, *)
struct RootTabShell: View {
    @Binding var selection: RootView.Tab
    let showsFeed: Bool
    let showsLibrary: Bool
    let showsDownloads: Bool
    let showsSearch: Bool
    let showsSettings: Bool
    @AppStorage("tabBarOrder") private var tabBarOrderRaw = TabBarOrder.defaultValue
    @AppStorage("showTabBarLabels") private var showTabBarLabels = true

    private let downloads = DownloadManager.shared

    private var activeDownloadsCount: Int {
        downloads.activeTasks.filter { snapshot in
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }.count
    }

    private var visibleOrdinaryTabs: [RootView.Tab] {
        TabBarOrder.visibleTabs(
            from: tabBarOrderRaw,
            feed: showsFeed,
            library: showsLibrary,
            downloads: showsDownloads,
            search: showsSearch,
            settings: showsSettings
        ).filter { $0 != .search }
    }

    @ViewBuilder
    var body: some View {
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
        } else {
            legacyTabShell
        }
    }

    /// iOS 17–25 compatibility. iOS 26 uses the modern `Tab` declarations above for its
    /// native Liquid Glass tab bar and a separate Search button.
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
        .overlay {
            if tab == selection {
                FloatingPlayerUnderlay()
            }
        }
    }

}
