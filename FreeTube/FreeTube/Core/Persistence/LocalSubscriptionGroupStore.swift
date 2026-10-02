import Foundation
import Observation

/// Persists group membership independently of YouTube and the subscription-feed cache.
@available(iOS 17.0, *)
@Observable
@MainActor
final class LocalSubscriptionGroupStore {
    static let shared = LocalSubscriptionGroupStore()

    nonisolated private static let defaultsKey = "com.leshko.freetube.subscriptionGroups.v1"
    private(set) var groups: [SubscriptionGroup] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([SubscriptionGroup].self, from: data) {
            groups = saved
        }
    }

    @discardableResult
    func add(name: String) -> Bool {
        guard let name = validName(name) else { return false }
        groups.append(SubscriptionGroup(id: UUID(), name: name, channelIDs: []))
        persist()
        return true
    }

    @discardableResult
    func rename(id: UUID, to name: String) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }),
              let name = validName(name, excluding: id) else { return false }
        groups[index].name = name
        persist()
        return true
    }

    func remove(id: UUID) {
        groups.removeAll { $0.id == id }
        persist()
    }

    func setMember(_ channelID: String, in groupID: UUID, isMember: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if isMember {
            groups[index].channelIDs.insert(channelID)
        } else {
            groups[index].channelIDs.remove(channelID)
        }
        persist()
    }

    func removeChannel(_ channelID: String) {
        var changed = false
        for index in groups.indices {
            changed = groups[index].channelIDs.remove(channelID) != nil || changed
        }
        if changed { persist() }
    }

    func replaceAll(with restored: [SubscriptionGroup], validChannelIDs: Set<String>) {
        var seen = Set<UUID>()
        groups = restored.compactMap { group in
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(group.id).inserted else { return nil }
            return SubscriptionGroup(
                id: group.id,
                name: name,
                channelIDs: group.channelIDs.intersection(validChannelIDs)
            )
        }
        persist()
    }

    private func validName(_ rawName: String, excluding id: UUID? = nil) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60,
              !groups.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return name
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
