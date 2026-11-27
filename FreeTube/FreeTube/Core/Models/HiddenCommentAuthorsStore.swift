import Foundation
import Observation

/// Local list of channel IDs whose comments are hidden in the player. Device-only; never synced.
@available(iOS 17.0, *)
@Observable
@MainActor
final class HiddenCommentAuthorsStore {
    struct Entry: Codable, Hashable, Identifiable, Sendable {
        let channelID: String
        let name: String

        var id: String { channelID }
    }

    static let shared = HiddenCommentAuthorsStore()
    static let defaultsKey = "com.leshko.freetube.hiddenCommentAuthors.v1"

    private(set) var entries: [Entry] = []
    private(set) var revision = 0

    private init() {
        entries = Self.readEntries()
    }

    func isHidden(channelID: String) -> Bool {
        let id = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        return entries.contains { $0.channelID == id }
    }

    func hides(_ comment: Comment) -> Bool {
        guard let channelID = comment.authorChannelID else { return false }
        return isHidden(channelID: channelID)
    }

    @discardableResult
    func hide(channelID: String, name: String) -> Bool {
        let id = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if let index = entries.firstIndex(where: { $0.channelID == id }) {
            if !trimmedName.isEmpty, entries[index].name != trimmedName {
                entries[index] = Entry(channelID: id, name: trimmedName)
                persist()
            }
            return false
        }
        entries.append(Entry(channelID: id, name: trimmedName.isEmpty ? id : trimmedName))
        persist()
        return true
    }

    func unhide(channelID: String) {
        let id = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let before = entries.count
        entries.removeAll { $0.channelID == id }
        if entries.count != before {
            persist()
        }
    }

    func remove(_ entry: Entry) {
        unhide(channelID: entry.channelID)
    }

    /// Backup restore writes UserDefaults directly, so refresh the in-memory copy afterward.
    func reload() {
        entries = Self.readEntries()
        revision &+= 1
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.defaultsKey)
        revision &+= 1
    }

    private static func readEntries() -> [Entry] {
        guard let text = UserDefaults.standard.string(forKey: defaultsKey),
              let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }
}
