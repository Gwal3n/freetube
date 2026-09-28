import Observation

/// Live selection is synchronous observable state. Temporary Library-start A/B diagnostic:
/// restore Feed startup after comparing navigation logs, keeping in-session selection intact.
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
