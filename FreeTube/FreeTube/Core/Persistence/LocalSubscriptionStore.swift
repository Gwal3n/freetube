import Foundation
import Observation

struct LocalSubscription: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var channelURL: URL?
    var thumbnailURL: URL?

    var channel: Channel {
        Channel(
            id: id,
            name: name,
            handle: nil,
            thumbnailURL: thumbnailURL,
            bannerURL: nil,
            subscriberCount: nil,
            videoCount: nil,
            isSubscribed: true,
            descriptionText: nil
        )
    }
}

enum LocalSubscriptionImportError: LocalizedError {
    case unreadableFile
    case invalidHeader
    case noChannels

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The selected file could not be read as UTF-8 CSV."
        case .invalidHeader: return "The CSV must contain Channel Id, Channel Url, and Channel Title columns."
        case .noChannels: return "No valid channels were found in the CSV."
        }
    }
}

/// Device-only source of truth for subscriptions. It deliberately does not depend on account
/// cookies: signing out, an expired YouTube session, and server subscription state cannot alter it.
@available(iOS 17.0, *)
@Observable
@MainActor
final class LocalSubscriptionStore {
    static let shared = LocalSubscriptionStore()

    nonisolated private static let defaultsKey = "com.leshko.freetube.localSubscriptions.v1"
    private(set) var subscriptions: [LocalSubscription] = []

    private init() {
        subscriptions = Self.readPersisted()
    }

    func contains(_ channelID: String) -> Bool {
        subscriptions.contains { $0.id == channelID }
    }

    nonisolated static func containsPersisted(_ channelID: String) -> Bool {
        readPersisted().contains { $0.id == channelID }
    }

    func add(_ channel: Channel) {
        let item = LocalSubscription(
            id: channel.id,
            name: channel.name.isEmpty ? channel.id : channel.name,
            channelURL: URL(string: "https://www.youtube.com/channel/\(channel.id)"),
            thumbnailURL: channel.thumbnailURL
        )
        upsert(item)
    }

    func remove(channelID: String) {
        let oldCount = subscriptions.count
        subscriptions.removeAll { $0.id == channelID }
        if subscriptions.count != oldCount { persist() }
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where subscriptions.indices.contains(index) {
            subscriptions.remove(at: index)
        }
        persist()
    }

    func removeAll() {
        subscriptions.removeAll()
        persist()
    }

    /// Imports YouTube/Google Takeout's subscription CSV format. Existing channels are updated,
    /// not duplicated, and channels already saved manually remain in the list.
    @discardableResult
    func importCSV(data: Data) throws -> Int {
        guard var text = String(data: data, encoding: .utf8) else {
            throw LocalSubscriptionImportError.unreadableFile
        }
        if text.first == "\u{feff}" { text.removeFirst() }

        let rows = Self.parseCSV(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard let header = rows.first else { throw LocalSubscriptionImportError.invalidHeader }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let idIndex = normalized.firstIndex(of: "channel id"),
              let urlIndex = normalized.firstIndex(of: "channel url"),
              let titleIndex = normalized.firstIndex(of: "channel title") else {
            throw LocalSubscriptionImportError.invalidHeader
        }

        var imported = 0
        for row in rows.dropFirst() {
            guard row.indices.contains(idIndex), row.indices.contains(titleIndex) else { continue }
            let id = row[idIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            let title = row[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlText = row.indices.contains(urlIndex)
                ? row[urlIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            upsert(LocalSubscription(
                id: id,
                name: title.isEmpty ? id : title,
                channelURL: URL(string: urlText),
                thumbnailURL: nil
            ), persistImmediately: false)
            imported += 1
        }
        guard imported > 0 else { throw LocalSubscriptionImportError.noChannels }
        sortAndPersist()
        return imported
    }

    private func upsert(_ item: LocalSubscription, persistImmediately: Bool = true) {
        if let index = subscriptions.firstIndex(where: { $0.id == item.id }) {
            var merged = item
            if merged.thumbnailURL == nil { merged.thumbnailURL = subscriptions[index].thumbnailURL }
            subscriptions[index] = merged
        } else {
            subscriptions.append(item)
        }
        if persistImmediately { sortAndPersist() }
    }

    private func sortAndPersist() {
        subscriptions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    nonisolated private static func readPersisted() -> [LocalSubscription] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let values = try? JSONDecoder().decode([LocalSubscription].self, from: data) else {
            return []
        }
        return values
    }

    /// Small RFC 4180-style parser supporting quoted titles, embedded commas, escaped quotes,
    /// and both LF and CRLF line endings.
    nonisolated private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character == "\n", !quoted {
                row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = next
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            rows.append(row)
        }
        return rows
    }
}
