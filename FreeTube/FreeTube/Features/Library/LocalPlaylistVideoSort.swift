import Foundation
import SwiftUI

/// Presentation-only order for a local playlist. Sorting never rewrites its saved manual order.
@available(iOS 17.0, *)
enum LocalPlaylistVideoSort: String, CaseIterable, Identifiable {
    case custom
    case title
    case length

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .custom: "Custom order"
        case .title: "Title (A–Z)"
        case .length: "Length (shortest first)"
        }
    }

    func ordered(_ videos: [Video]) -> [Video] {
        guard self != .custom else { return videos }
        // Include each video's original index so equal titles/durations retain manual order.
        return videos.enumerated().sorted { left, right in
            switch self {
            case .custom:
                return left.offset < right.offset
            case .title:
                let comparison = left.element.title.localizedStandardCompare(right.element.title)
                return comparison == .orderedSame
                    ? left.offset < right.offset : comparison == .orderedAscending
            case .length:
                let leftDuration = usableDuration(left.element.duration)
                let rightDuration = usableDuration(right.element.duration)
                if let leftDuration, let rightDuration {
                    return leftDuration == rightDuration
                        ? left.offset < right.offset : leftDuration < rightDuration
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
}
