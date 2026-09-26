import Observation

/// Live selection is synchronous observable state. Scene storage is used only to restore it
/// once, never as the TabView's live getter during a player or system-alert presentation.
@available(iOS 17.0, *)
@MainActor
@Observable
final class RootTabSelection {
    private(set) var selected: RootView.Tab = .feed
    private var hasRestored = false

    func restore(rawValue: String, showsFeed: Bool) {
        guard !hasRestored else { return }
        hasRestored = true
        select(RootView.Tab(rawValue: rawValue) ?? .feed, showsFeed: showsFeed)
    }

    func select(_ tab: RootView.Tab, showsFeed: Bool) {
        selected = tab == .feed && !showsFeed ? .search : tab
    }

    func updateFeedVisibility(_ showsFeed: Bool) {
        if !showsFeed && selected == .feed { selected = .search }
    }
}
