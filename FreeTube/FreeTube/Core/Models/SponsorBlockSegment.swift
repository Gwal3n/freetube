import Foundation

struct SponsorBlockSegment: Hashable, Sendable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let category: SponsorBlockCategory
    /// SponsorBlock chapter names; other categories do not carry a display title.
    let title: String?

    init(
        id: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        category: SponsorBlockCategory,
        title: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.category = category
        self.title = title
    }
}
