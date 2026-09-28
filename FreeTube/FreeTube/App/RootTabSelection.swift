import Observation

/// Live selection is synchronous observable state. Each launch starts on Feed (Search if Feed
/// is hidden). In-session selection survives sheet and player presentations.
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
