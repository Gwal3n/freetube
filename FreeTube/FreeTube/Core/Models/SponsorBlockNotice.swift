import Foundation

struct SponsorBlockNotice: Identifiable, Equatable {
    let id = UUID()
    let category: SponsorBlockCategory
    let originalStartTime: TimeInterval
}
