import Foundation

/// Ordinary tabs can be reordered without replacing the native tab bar.
/// Search retains the system search role on iOS 26 and is always last elsewhere.
@available(iOS 17.0, *)
enum TabBarOrder {
    static let defaultValue = "feed,library,downloads,settings"
    static let defaultTabs: [RootView.Tab] = [.feed, .library, .downloads, .settings]

    static func tabs(from rawValue: String) -> [RootView.Tab] {
        var result: [RootView.Tab] = []
        for component in rawValue.split(separator: ",") {
            guard let tab = RootView.Tab(rawValue: String(component)),
                  tab != .search, !result.contains(tab) else { continue }
            result.append(tab)
        }
        for tab in defaultTabs where !result.contains(tab) {
            result.append(tab)
        }
        return result
    }

    static func rawValue(for tabs: [RootView.Tab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }

    static func visibleTabs(
        from rawValue: String,
        feed: Bool,
        library: Bool,
        downloads: Bool,
        search: Bool,
        settings: Bool
    ) -> [RootView.Tab] {
        // Settings remains reachable if Library, its other entry point, is hidden.
        let showsSettings = settings || !library
        var tabs = tabs(from: rawValue).filter { tab in
            switch tab {
            case .feed: return feed
            case .library: return library
            case .downloads: return downloads
            case .settings: return showsSettings
            case .search: return false
            }
        }
        if search { tabs.append(.search) }
        return tabs
    }
}
