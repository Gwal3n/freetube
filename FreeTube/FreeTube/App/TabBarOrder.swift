import Foundation

/// The three ordinary tabs may be reordered without replacing the native tab bar.
/// Search remains the system search tab on iOS 26 and is always presented last elsewhere.
@available(iOS 17.0, *)
enum TabBarOrder {
    static let defaultValue = "feed,library,downloads"
    static let defaultTabs: [RootView.Tab] = [.feed, .library, .downloads]

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
}
