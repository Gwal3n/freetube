import Foundation

struct SponsorBlockNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case skipped
        case prompt(endTime: TimeInterval)
    }

    let id = UUID()
    let category: SponsorBlockCategory
    let originalStartTime: TimeInterval
    let kind: Kind
}
