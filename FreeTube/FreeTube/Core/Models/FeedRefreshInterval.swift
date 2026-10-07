import Foundation

/// Minimum time between automatic subscription-feed requests while Feed is selected.
enum FeedRefreshInterval: String, CaseIterable, Identifiable {
    case hourly
    case everySixHours
    case everyTwelveHours
    case daily

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hourly: 60 * 60
        case .everySixHours: 6 * 60 * 60
        case .everyTwelveHours: 12 * 60 * 60
        case .daily: 24 * 60 * 60
        }
    }
}
