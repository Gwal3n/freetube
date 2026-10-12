import Foundation

struct SponsorBlockSegment: Hashable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let category: SponsorBlockCategory
    /// SponsorBlock chapter names; other categories do not carry a display title.
    let title: String?
    /// A whole-video annotation, never a time range to skip or seek through.
    let isFullVideoLabel: Bool

    init(
        id: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        category: SponsorBlockCategory,
        title: String? = nil,
        isFullVideoLabel: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.category = category
        self.title = title
        self.isFullVideoLabel = isFullVideoLabel
    }

    /// SponsorBlock displays one full-video label, in this order, when submissions overlap.
    static func primaryFullVideoLabel(in segments: [SponsorBlockSegment]) -> SponsorBlockCategory? {
        [.sponsor, .exclusiveAccess, .selfPromotion].first { category in
            segments.contains { $0.isFullVideoLabel && $0.category == category }
        }
    }
}
