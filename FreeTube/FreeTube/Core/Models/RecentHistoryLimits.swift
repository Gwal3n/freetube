import Foundation

/// User-selected caps for device-local recent searches and recent channels. Saving beyond the cap
/// drops the oldest entries; lowering it hides the excess immediately and trims on the next save.
enum RecentHistoryLimits {
    static let searchKey = "recentSearchLimit"
    static let channelKey = "recentChannelLimit"
    static let range = 1...500
    static let defaultSearchLimit = 20
    static let defaultChannelLimit = 12

    static func searchLimit(_ defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: searchKey)
        return value > 0 ? min(value, range.upperBound) : defaultSearchLimit
    }

    static func channelLimit(_ defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: channelKey)
        return value > 0 ? min(value, range.upperBound) : defaultChannelLimit
    }
}
