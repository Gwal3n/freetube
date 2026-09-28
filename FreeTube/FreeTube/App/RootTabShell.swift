import SwiftUI

/// A stable native tab owner independent of playback artwork, presentation, and gesture updates.
@available(iOS 17.0, *)
struct RootTabShell: View {
    @Binding var selection: RootView.Tab
    let showsFeed: Bool
    let searchActivation: Int
    let feedNavigationRequest: AppNavigationRequest?
    let downloadsNavigationRequest: AppNavigationRequest?
    let searchNavigationRequest: AppNavigationRequest?

    private let downloads = DownloadManager.shared

    private var activeDownloadsCount: Int {
        downloads.activeTasks.filter { snapshot in
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }.count
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $selection) {
                if showsFeed {
                    SwiftUI.Tab("Feed", systemImage: "rectangle.stack", value: RootView.Tab.feed) {
                        SubscriptionFeedScreen(navigationRequest: feedNavigationRequest)
                    }
                }

                SwiftUI.Tab("Library", systemImage: "play.square.stack", value: RootView.Tab.library) {
                    LibraryScreen()
                }

                SwiftUI.Tab("Downloads", systemImage: "arrow.down.circle", value: RootView.Tab.downloads) {
                    DownloadsScreen(navigationRequest: downloadsNavigationRequest)
                }
                .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)

                SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: RootView.Tab.search, role: .search) {
                    HomeScreen(searchActivation: searchActivation, navigationRequest: searchNavigationRequest)
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
            if showsFeed {
                SubscriptionFeedScreen(navigationRequest: feedNavigationRequest)
                    .tabItem { Label("Feed", systemImage: "rectangle.stack") }
                    .tag(RootView.Tab.feed)
            }

            HomeScreen(searchActivation: searchActivation, navigationRequest: searchNavigationRequest)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(RootView.Tab.search)

            LibraryScreen()
                .tabItem { Label("Library", systemImage: "play.square.stack") }
                .tag(RootView.Tab.library)

            DownloadsScreen(navigationRequest: downloadsNavigationRequest)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .badge(activeDownloadsCount > 0 ? activeDownloadsCount : 0)
                .tag(RootView.Tab.downloads)
        }
    }

}
