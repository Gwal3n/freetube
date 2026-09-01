import Foundation

struct SponsorBlockSegment: Hashable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let category: SponsorBlockCategory
}
