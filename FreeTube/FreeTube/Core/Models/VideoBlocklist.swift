import Foundation
import Observation

/// Device-local presentation rules. Blocking never removes a subscription, download, history
/// entry, or playlist item; turning a rule off makes the original content visible again.
@available(iOS 17.0, *)
@Observable
@MainActor
final class VideoBlocklist {
    struct ChannelRule: Codable, Hashable, Identifiable {
        let channelID: String?
        let name: String

        var id: String { channelID ?? "name:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))" }
    }

    struct Rules: Codable, Equatable {
        var hideShorts = false
        var keywords: [String] = []
        var channels: [ChannelRule] = []

        var isActive: Bool { hideShorts || !keywords.isEmpty || !channels.isEmpty }
    }

    static let shared = VideoBlocklist()
    static let defaultsKey = "com.leshko.freetube.videoBlocklist.v1"

    private(set) var rules: Rules
    private(set) var revision = 0

    private init() {
        rules = Self.readRules()
    }

    var hideShorts: Bool {
        get { rules.hideShorts }
        set {
            rules.hideShorts = newValue
            persist()
        }
    }

    @discardableResult
    func addKeyword(_ input: String) -> Bool {
        let keyword = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword.count <= 80,
              !rules.keywords.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame })
        else { return false }
        rules.keywords.append(keyword)
        persist()
        return true
    }

    func removeKeyword(_ keyword: String) {
        rules.keywords.removeAll { $0 == keyword }
        persist()
    }

    /// Accept an exact channel name, a UC... channel ID, or a /channel/ URL. Handles cannot be
    /// matched reliably against video rows because YouTube does not return a handle on every row.
    @discardableResult
    func addChannel(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 160 else { return false }
        let channelID: String?
        if let url = URL(string: value), url.scheme != nil {
            guard let parsed = YouTubeIncomingLink.parse(url),
                  case .channel(let id) = parsed else { return false }
            channelID = id
        } else if value.hasPrefix("UC"), value.count == 24 {
            channelID = value
        } else {
            guard !value.hasPrefix("@") else { return false }
            channelID = nil
        }
        return insertChannel(ChannelRule(channelID: channelID, name: channelID ?? value))
    }

    func block(_ channel: Channel) {
        blockChannel(id: channel.id, name: channel.name)
    }

    func blockChannel(id: String, name: String) {
        guard !id.isEmpty || !name.isEmpty else { return }
        _ = insertChannel(ChannelRule(channelID: id.isEmpty ? nil : id, name: name.isEmpty ? id : name))
    }

    func unblock(_ channel: Channel) {
        rules.channels.removeAll { rule in
            rule.channelID == channel.id || same(rule.name, channel.name)
        }
        persist()
    }

    func removeChannel(_ rule: ChannelRule) {
        rules.channels.removeAll { $0.id == rule.id }
        persist()
    }

    func blocks(_ video: Video) -> Bool {
        (rules.hideShorts && video.isShort)
            || blocks(title: video.title, channelID: video.channelID, channelName: video.channelName)
    }

    func blocks(_ channel: Channel) -> Bool {
        matchesChannel(id: channel.id, name: channel.name)
    }

    func blocks(_ playlist: Playlist) -> Bool {
        matchesChannel(id: playlist.channelID, name: playlist.channelName)
            || matchesKeyword(in: playlist.title)
    }

    func blocks(title: String, channelID: String?, channelName: String?) -> Bool {
        matchesKeyword(in: title) || matchesChannel(id: channelID, name: channelName)
    }

    /// Backup restore writes UserDefaults directly, so the in-memory observable copy must be
    /// refreshed afterward without making the backup service aware of SwiftUI views.
    func reload() {
        rules = Self.readRules()
        revision &+= 1
    }

    private func insertChannel(_ rule: ChannelRule) -> Bool {
        guard !rules.channels.contains(where: { existing in
            (rule.channelID != nil && existing.channelID == rule.channelID)
                || same(existing.name, rule.name)
        }) else { return false }
        rules.channels.append(rule)
        persist()
        return true
    }

    private func matchesChannel(id: String?, name: String?) -> Bool {
        rules.channels.contains { rule in
            (rule.channelID != nil && rule.channelID == id)
                || (name.map { same(rule.name, $0) } ?? false)
        }
    }

    private func matchesKeyword(in text: String) -> Bool {
        rules.keywords.contains { text.localizedStandardContains($0) }
    }

    private func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.defaultsKey)
        revision &+= 1
    }

    private static func readRules() -> Rules {
        guard let text = UserDefaults.standard.string(forKey: defaultsKey),
              let data = text.data(using: .utf8),
              let rules = try? JSONDecoder().decode(Rules.self, from: data) else { return Rules() }
        return rules
    }
}
