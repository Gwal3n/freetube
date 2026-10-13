import Foundation

/// Local persistence and ordering rules for explicit Play Next / Add to Queue choices.
/// PlayerStateManager retains the observable array and decides when these rules apply.
@MainActor
enum PlayerManualQueueStore {
    private static let defaultsKey = "manualQueue"

    static func restore(from defaults: UserDefaults = .standard) -> [Video] {
        guard let encoded = defaults.string(forKey: defaultsKey),
              let data = encoded.data(using: .utf8),
              let videos = try? JSONDecoder().decode([Video].self, from: data) else { return [] }
        return videos
    }

    static func persist(_ videos: [Video], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(videos),
              let encoded = String(data: data, encoding: .utf8) else { return }
        defaults.set(encoded, forKey: defaultsKey)
    }

    static func insertingNext(_ video: Video, into videos: [Video]) -> [Video] {
        [video] + videos.filter { $0.id != video.id }
    }

    static func appending(_ video: Video, to videos: [Video]) -> [Video] {
        guard !videos.contains(where: { $0.id == video.id }) else { return videos }
        return videos + [video]
    }

    static func removing(_ videoID: String, from videos: [Video]) -> [Video] {
        videos.filter { $0.id != videoID }
    }

    static func restoring(_ video: Video, at index: Int, to videos: [Video]) -> [Video] {
        guard !videos.contains(where: { $0.id == video.id }) else { return videos }
        var restored = videos
        restored.insert(video, at: min(index, restored.endIndex))
        return restored
    }

    static func restoring(_ removedVideos: [Video], to videos: [Video]) -> [Video] {
        let existingIDs = Set(videos.map(\.id))
        return removedVideos.filter { !existingIDs.contains($0.id) } + videos
    }

    /// Reorder only visible rows while blocked entries retain their existing slots.
    static func reordered(
        _ videos: [Video],
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
        isBlocked: (Video) -> Bool
    ) -> [Video]? {
        guard !offsets.isEmpty else { return nil }
        var visible = videos.filter { !isBlocked($0) }
        guard offsets.allSatisfy({ visible.indices.contains($0) }) else { return nil }
        let moved = offsets.sorted().map { visible[$0] }
        for index in offsets.sorted(by: >) {
            visible.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), visible.endIndex)
        visible.insert(contentsOf: moved, at: insertionIndex)
        var reordered = visible.makeIterator()
        return videos.map { item in
            isBlocked(item) ? item : (reordered.next() ?? item)
        }
    }
}
