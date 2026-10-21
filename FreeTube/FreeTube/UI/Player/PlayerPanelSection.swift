import Foundation

/// Stable identities for the collapsible sections below the player's metadata.
enum PlayerPanelSection: String, CaseIterable, Hashable, Identifiable {
    case savedMoments
    case queue
    case upNext
    case comments

    static let defaultOrder = allCases.map(\.rawValue).joined(separator: ",")

    var id: String { rawValue }

    var title: String {
        switch self {
        case .savedMoments: String(localized: "Saved moments")
        case .queue: String(localized: "Queue")
        case .upNext: String(localized: "Up next")
        case .comments: String(localized: "Comments")
        }
    }

    var symbol: String {
        switch self {
        case .savedMoments: "bookmark"
        case .queue: "text.line.first.and.arrowtriangle.forward"
        case .upNext: "play.rectangle.on.rectangle"
        case .comments: "text.bubble"
        }
    }

    static func ordered(from storedValue: String) -> [Self] {
        var seen = Set<Self>()
        let saved = storedValue.split(separator: ",")
            .compactMap { Self(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        return saved + allCases.filter { seen.insert($0).inserted }
    }

    static func storedValue(for sections: [Self]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
}
