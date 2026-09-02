import Foundation

/// SponsorBlock segment categories supported by the first-party player integration.
enum SponsorBlockCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case sponsor
    case selfPromotion = "selfpromo"
    case interaction
    case intro
    case outro
    case highlight = "poi_highlight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sponsor: return String(localized: "Sponsors")
        case .selfPromotion: return String(localized: "Self-promotion")
        case .interaction: return String(localized: "Interaction reminders")
        case .intro: return String(localized: "Intros")
        case .outro: return String(localized: "Outros")
        case .highlight: return String(localized: "Highlights")
        }
    }
}

enum SponsorBlockBehavior: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case showOnly
    case autoSkip
    case ask

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return String(localized: "Disabled")
        case .showOnly: return String(localized: "Show only")
        case .autoSkip: return String(localized: "Automatically skip")
        case .ask: return String(localized: "Ask")
        }
    }

    static func choices(for category: SponsorBlockCategory) -> [SponsorBlockBehavior] {
        category == .highlight ? [.disabled, .showOnly, .ask] : [.disabled, .showOnly, .autoSkip]
    }
}
