import Observation

/// Live selection is synchronous observable state. Each app launch begins on Feed (or Search
/// when Feed is hidden), while sheet/player reappearances preserve the in-session selection.
@available(iOS 17.0, *)
@MainActor
@Observable
final class RootTabSelection {
    private(set) var selected: RootView.Tab = .feed
    private var hasStarted = false

    func start(showsFeed: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        select(.feed, showsFeed: showsFeed)
    }

    func select(_ tab: RootView.Tab, showsFeed: Bool) {
        selected = tab == .feed && !showsFeed ? .search : tab
    }

    func updateFeedVisibility(_ showsFeed: Bool) {
        if !showsFeed && selected == .feed { selected = .search }
    }
}
