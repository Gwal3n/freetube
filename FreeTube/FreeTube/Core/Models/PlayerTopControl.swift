import Foundation

enum PlayerTopControl: String, CaseIterable, Identifiable, Sendable {
    case speed
    case loop
    case mute
    case fullscreen
    case autoplay
    case audioOnly
    case quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: return String(localized: "Speed")
        case .loop: return String(localized: "Loop")
        case .mute: return String(localized: "Mute")
        case .fullscreen: return String(localized: "Fullscreen")
        case .autoplay: return String(localized: "Autoplay")
        case .audioOnly: return String(localized: "Audio only")
        case .quality: return String(localized: "Quality limit")
        }
    }

    var systemImage: String {
        switch self {
        case .speed: return "gauge.with.dots.needle.67percent"
        case .loop: return "repeat.1"
        case .mute: return "speaker.slash"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .autoplay: return "play.circle"
        case .audioOnly: return "headphones"
        case .quality: return "slider.horizontal.3"
        }
    }

    static let defaultOrder: [PlayerTopControl] = [.autoplay, .loop, .mute, .audioOnly, .fullscreen, .speed]

    static func decodeOrder(_ rawValue: String) -> [PlayerTopControl] {
        let stored = rawValue.split(separator: ",").compactMap { PlayerTopControl(rawValue: String($0)) }
        var result = stored.reduce(into: [PlayerTopControl]()) { partial, control in
            if !partial.contains(control) { partial.append(control) }
        }
        for control in defaultOrder where !result.contains(control) {
            result.append(control)
        }
        return result
    }

    static func encodeOrder(_ controls: [PlayerTopControl]) -> String {
        controls.map(\.rawValue).joined(separator: ",")
    }

    static func decodeHidden(_ rawValue: String) -> Set<PlayerTopControl> {
        Set(rawValue.split(separator: ",").compactMap { PlayerTopControl(rawValue: String($0)) })
    }

    static func encodeHidden(_ controls: Set<PlayerTopControl>) -> String {
        controls.map(\.rawValue).sorted().joined(separator: ",")
    }
}
