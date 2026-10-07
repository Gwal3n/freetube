import Foundation

/// A single placement for every optional player control. The fixed collapse and transport
/// buttons are intentionally outside this layout so they can never be hidden by accident.
struct PlayerControlLayout: Equatable {
    enum Section: String, CaseIterable, Identifiable {
        case onPlayer
        case moreMenu
        case hidden

        var id: String { rawValue }

        var title: String {
            switch self {
            case .onPlayer: return String(localized: "On player")
            case .moreMenu: return String(localized: "More menu")
            case .hidden: return String(localized: "Hidden")
            }
        }
    }

    static let standard = PlayerControlLayout(
        onPlayer: [.audioOnly, .fullscreen, .speed],
        moreMenu: [.quality, .captions, .autoplay, .loop, .mute, .sleepTimer],
        hidden: []
    )

    private(set) var onPlayer: [PlayerTopControl]
    private(set) var moreMenu: [PlayerTopControl]
    private(set) var hidden: [PlayerTopControl]

    init(onPlayer: [PlayerTopControl], moreMenu: [PlayerTopControl], hidden: [PlayerTopControl]) {
        var seen = Set<PlayerTopControl>()
        self.onPlayer = onPlayer.filter { seen.insert($0).inserted }
        self.moreMenu = moreMenu.filter { seen.insert($0).inserted }
        self.hidden = hidden.filter { seen.insert($0).inserted }
        self.moreMenu += PlayerTopControl.allCases.filter { seen.insert($0).inserted }
    }

    func controls(in section: Section) -> [PlayerTopControl] {
        switch section {
        case .onPlayer: return onPlayer
        case .moreMenu: return moreMenu
        case .hidden: return hidden
        }
    }

    mutating func move(_ control: PlayerTopControl, to section: Section, before target: PlayerTopControl? = nil) {
        guard PlayerTopControl.allCases.contains(control) else { return }
        if target == control { return }
        onPlayer.removeAll { $0 == control }
        moreMenu.removeAll { $0 == control }
        hidden.removeAll { $0 == control }

        switch section {
        case .onPlayer:
            onPlayer.insert(control, at: target.flatMap { onPlayer.firstIndex(of: $0) } ?? onPlayer.endIndex)
        case .moreMenu:
            moreMenu.insert(control, at: target.flatMap { moreMenu.firstIndex(of: $0) } ?? moreMenu.endIndex)
        case .hidden:
            hidden.insert(control, at: target.flatMap { hidden.firstIndex(of: $0) } ?? hidden.endIndex)
        }
    }

    /// Reorder within one section using the offsets supplied by SwiftUI's native List editing.
    /// Cross-section placement remains a separate, explicit menu action.
    mutating func reorder(in section: Section, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let current = controls(in: section)
        guard !offsets.isEmpty,
              offsets.allSatisfy({ current.indices.contains($0) }),
              (0...current.count).contains(destination) else { return }

        let moving = offsets.sorted().map { current[$0] }
        var remaining = current.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map { $0.element }
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertion)

        switch section {
        case .onPlayer: onPlayer = remaining
        case .moreMenu: moreMenu = remaining
        case .hidden: hidden = remaining
        }
    }

    /// Compact, human-readable UserDefaults value. Empty sections are retained between pipes.
    var encoded: String {
        [onPlayer, moreMenu, hidden]
            .map { $0.map(\.rawValue).joined(separator: ",") }
            .joined(separator: "|")
    }

    static func restored(
        from rawValue: String,
        legacyOrder: String,
        legacyHidden: String
    ) -> PlayerControlLayout {
        let sections = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        if sections.count == 3 {
            func decode(_ text: Substring) -> [PlayerTopControl] {
                text.split(separator: ",").compactMap { PlayerTopControl(rawValue: String($0)) }
            }
            return PlayerControlLayout(
                onPlayer: decode(sections[0]),
                moreMenu: decode(sections[1]),
                hidden: decode(sections[2])
            )
        }

        let oldDefault = PlayerTopControl.encodeOrder(PlayerTopControl.defaultOrder)
        if legacyOrder == oldDefault && legacyHidden.isEmpty { return .standard }

        let order = PlayerTopControl.decodeOrder(legacyOrder)
        let hidden = PlayerTopControl.decodeHidden(legacyHidden)
        return PlayerControlLayout(
            onPlayer: order.filter { !hidden.contains($0) },
            moreMenu: [.quality],
            hidden: order.filter { hidden.contains($0) }
        )
    }
}
