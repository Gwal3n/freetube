import Observation

/// Live selection is synchronous observable state. Library-first is temporary while Library's
/// tab-hosted navigation is repaired; preserve selection through presentations in-session.
@available(iOS 17.0, *)
@MainActor
@Observable
final class RootTabSelection {
    private(set) var selected: RootView.Tab = .feed
    private var hasStarted = false

    func start(showsFeed: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        select(.library, showsFeed: showsFeed)
    }

    func select(_ tab: RootView.Tab, showsFeed: Bool) {
        selected = tab == .feed && !showsFeed ? .search : tab
    }

    func updateFeedVisibility(_ showsFeed: Bool) {
        if !showsFeed && selected == .feed { selected = .search }
    }
}
