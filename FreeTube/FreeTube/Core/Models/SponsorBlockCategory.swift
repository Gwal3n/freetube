import Foundation

/// SponsorBlock segment categories supported by the first-party player integration.
enum SponsorBlockCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case sponsor
    case selfPromotion = "selfpromo"
    case interaction
    case intro
    case outro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sponsor: return String(localized: "Sponsors")
        case .selfPromotion: return String(localized: "Self-promotion")
        case .interaction: return String(localized: "Interaction reminders")
        case .intro: return String(localized: "Intros")
        case .outro: return String(localized: "Outros")
        }
    }
}
