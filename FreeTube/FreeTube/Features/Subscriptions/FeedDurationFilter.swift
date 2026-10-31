import Foundation

@available(iOS 17.0, *)
enum FeedDurationFilter: String, CaseIterable, Identifiable {
    case all, underFourMinutes, fourToTwentyMinutes, overTwentyMinutes, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Any length"
        case .underFourMinutes: "Under 4 minutes"
        case .fourToTwentyMinutes: "4–20 minutes"
        case .overTwentyMinutes: "Over 20 minutes"
        case .custom: "Custom range…"
        }
    }

    func includes(
        _ duration: TimeInterval?,
        minimumMinutes: Int,
        maximumMinutes: Int
    ) -> Bool {
        guard self != .all else { return true }
        guard let duration, duration.isFinite, duration > 0 else { return false }
        return switch self {
        case .all: true
        case .underFourMinutes: duration < 240
        case .fourToTwentyMinutes: duration >= 240 && duration <= 1200
        case .overTwentyMinutes: duration > 1200
        case .custom:
            duration >= TimeInterval(max(0, minimumMinutes)) * 60
                && (maximumMinutes == 0 || duration <= TimeInterval(maximumMinutes) * 60)
        }
    }
}
