import Foundation
import SwiftUI

/// Keeps category colors consistent across the timeline, skip notice, and video label.
struct SponsorBlockColorPalette {
    private struct Entry: Codable {
        var usesCustomColor: Bool
        var hex: String
    }

    private var entries: [String: Entry]

    init(json: String) {
        let decoded = json.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = decoded.filter {
            SponsorBlockCategory(rawValue: $0.key) != nil && WatchIndicatorStyle.color(hex: $0.value.hex) != nil
        }
    }

    func usesCustomColor(for category: SponsorBlockCategory) -> Bool {
        entries[category.rawValue]?.usesCustomColor == true
    }

    func color(for category: SponsorBlockCategory) -> Color {
        if let entry = entries[category.rawValue], entry.usesCustomColor,
           let color = WatchIndicatorStyle.color(hex: entry.hex) {
            return color
        }
        return Self.defaultColor(for: category)
    }

    mutating func setCustomColorEnabled(_ enabled: Bool, for category: SponsorBlockCategory) {
        var entry = entries[category.rawValue]
            ?? Entry(usesCustomColor: false, hex: WatchIndicatorStyle.hex(color: Self.defaultColor(for: category)))
        entry.usesCustomColor = enabled
        entries[category.rawValue] = entry
    }

    mutating func setColor(_ color: Color, for category: SponsorBlockCategory) {
        entries[category.rawValue] = Entry(usesCustomColor: true, hex: WatchIndicatorStyle.hex(color: color))
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(entries),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }

    static func defaultColor(for category: SponsorBlockCategory) -> Color {
        switch category {
        case .sponsor: .green
        case .selfPromotion: .yellow
        case .exclusiveAccess: Color(red: 0, green: 138.0 / 255, blue: 92.0 / 255)
        case .interaction: .pink
        case .intro: .cyan
        case .outro: .blue
        case .preview: Color(red: 0, green: 143.0 / 255, blue: 214.0 / 255)
        case .hook: Color(red: 1, green: 128.0 / 255, blue: 0)
        case .musicOfftopic: Color(red: 1, green: 153.0 / 255, blue: 0)
        case .filler: Color(red: 115.0 / 255, green: 0, blue: 1)
        case .highlight: .purple
        case .chapter: .white
        }
    }
}
