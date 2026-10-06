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

    /// Four controls plus the overflow button leave room for the fixed collapse button on small
    /// phones, while landscape still has space for its one-line title.
    static let maximumOnPlayer = 4

    static let standard = PlayerControlLayout(
        onPlayer: [.audioOnly, .fullscreen, .speed],
        moreMenu: [.quality, .autoplay, .loop, .mute, .sleepTimer],
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
        if self.onPlayer.count > Self.maximumOnPlayer {
            self.moreMenu.insert(contentsOf: self.onPlayer.dropFirst(Self.maximumOnPlayer), at: 0)
            self.onPlayer = Array(self.onPlayer.prefix(Self.maximumOnPlayer))
        }
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
            if onPlayer.count > Self.maximumOnPlayer,
               let displacedIndex = onPlayer.lastIndex(where: { $0 != control }) {
                moreMenu.insert(onPlayer.remove(at: displacedIndex), at: 0)
            }
        case .moreMenu:
            moreMenu.insert(control, at: target.flatMap { moreMenu.firstIndex(of: $0) } ?? moreMenu.endIndex)
        case .hidden:
            hidden.insert(control, at: target.flatMap { hidden.firstIndex(of: $0) } ?? hidden.endIndex)
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
