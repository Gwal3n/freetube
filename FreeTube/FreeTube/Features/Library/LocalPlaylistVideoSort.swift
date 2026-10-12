import Foundation
import SwiftUI

/// Presentation-only order for a local playlist. Sorting never rewrites its saved manual order.
@available(iOS 17.0, *)
enum LocalPlaylistVideoSort: String, CaseIterable, Identifiable {
    case custom
    case title
    case titleDescending
    case newest
    case oldest
    case mostViewed
    case leastViewed
    case length
    case lengthLongest

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .custom: "Custom order"
        case .title: "Title (A–Z)"
        case .titleDescending: "Title (Z–A)"
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .mostViewed: "Most viewed first"
        case .leastViewed: "Least viewed first"
        case .length: "Length (shortest first)"
        case .lengthLongest: "Length (longest first)"
        }
    }

    func ordered(_ videos: [Video]) -> [Video] {
        guard self != .custom else { return videos }
        let referenceDate = Date.now
        // Include each video's original index so equal titles/durations retain manual order.
        return videos.enumerated().sorted { left, right in
            switch self {
            case .custom:
                return left.offset < right.offset
            case .title, .titleDescending:
                let comparison = left.element.title.localizedStandardCompare(right.element.title)
                if comparison == .orderedSame { return left.offset < right.offset }
                return self == .title ? comparison == .orderedAscending : comparison == .orderedDescending
            case .newest, .oldest:
                return compareOptional(
                    left.element.estimatedPublishedAt(relativeTo: referenceDate),
                    right.element.estimatedPublishedAt(relativeTo: referenceDate),
                    leftIndex: left.offset, rightIndex: right.offset,
                    ascending: self == .oldest
                )
            case .mostViewed, .leastViewed:
                return compareOptional(
                    left.element.viewCount, right.element.viewCount,
                    leftIndex: left.offset, rightIndex: right.offset,
                    ascending: self == .leastViewed
                )
            case .length, .lengthLongest:
                let leftDuration = usableDuration(left.element.duration)
                let rightDuration = usableDuration(right.element.duration)
                if let leftDuration, let rightDuration {
                    return leftDuration == rightDuration
                        ? left.offset < right.offset
                        : self == .length ? leftDuration < rightDuration : leftDuration > rightDuration
                }
                if leftDuration != nil { return true }
                if rightDuration != nil { return false }
                return left.offset < right.offset
            }
        }.map { $0.element }
    }

    private func usableDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private func compareOptional<Value: Comparable>(
        _ left: Value?, _ right: Value?,
        leftIndex: Int, rightIndex: Int, ascending: Bool
    ) -> Bool {
        if let left, let right {
            if left == right { return leftIndex < rightIndex }
            return ascending ? left < right : left > right
        }
        if left != nil { return true }
        if right != nil { return false }
        return leftIndex < rightIndex
    }
}
