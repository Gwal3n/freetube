import Foundation

/// SponsorBlock segment categories supported by the first-party player integration.
enum SponsorBlockCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case sponsor
    case selfPromotion = "selfpromo"
    case exclusiveAccess = "exclusive_access"
    case interaction
    case intro
    case outro
    case preview
    case hook
    case musicOfftopic = "music_offtopic"
    case filler
    case highlight = "poi_highlight"
    case chapter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sponsor: return String(localized: "Sponsors")
        case .selfPromotion: return String(localized: "Self-promotion")
        case .exclusiveAccess: return String(localized: "Exclusive access")
        case .interaction: return String(localized: "Interaction reminders")
        case .intro: return String(localized: "Intros")
        case .outro: return String(localized: "Outros")
        case .preview: return String(localized: "Previews")
        case .hook: return String(localized: "Hooks and greetings")
        case .musicOfftopic: return String(localized: "Non-music sections")
        case .filler: return String(localized: "Filler")
        case .highlight: return String(localized: "Highlights")
        case .chapter: return String(localized: "Community chapters")
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
        switch category {
        case .highlight: return [.disabled, .showOnly, .ask]
        case .exclusiveAccess, .chapter: return [.disabled, .showOnly]
        default: return [.disabled, .showOnly, .autoSkip]
        }
    }
}
