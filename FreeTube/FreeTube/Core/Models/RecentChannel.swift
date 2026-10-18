import Foundation

/// A bounded, device-local channel visit. No network request is needed to display it in Search.
struct RecentChannel: Codable, Identifiable {
    static let maximumCount = 3

    let id: String
    let name: String
    let handle: String?
    let thumbnailURL: URL?

    var channel: Channel {
        Channel(id: id, name: name, handle: handle, thumbnailURL: thumbnailURL,
                bannerURL: nil, subscriberCount: nil, videoCount: nil,
                isSubscribed: false, descriptionText: nil)
    }

    static func entries(from json: String) -> [RecentChannel] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decoded = (try? JSONDecoder().decode([RecentChannel].self, from: data)) ?? []
        return Array(decoded.prefix(maximumCount))
    }

    static func json(from entries: [RecentChannel]) -> String? {
        guard let data = try? JSONEncoder().encode(Array(entries.prefix(maximumCount))) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func record(_ channel: Channel, defaults: UserDefaults = .standard) {
        let savesHistory = defaults.object(forKey: "saveSearchHistory") as? Bool ?? true
        let skipsIncognitoHistory = defaults.object(forKey: "incognitoSkipSearchHistory") as? Bool ?? true
        guard savesHistory,
              !(defaults.bool(forKey: "incognitoEnabled") && skipsIncognitoHistory),
              !channel.id.isEmpty else { return }
        let key = "recentChannelsJSON"
        var entries = entries(from: defaults.string(forKey: key) ?? "[]")
        entries.removeAll { $0.id == channel.id }
        entries.insert(RecentChannel(id: channel.id, name: channel.name,
                                     handle: channel.handle, thumbnailURL: channel.thumbnailURL), at: 0)
        if let json = json(from: entries) {
            defaults.set(json, forKey: key)
        }
    }
}
