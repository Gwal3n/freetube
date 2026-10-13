import Foundation

/// Browser-style Previous/Next history, separate from the visible recommendation queue.
/// A new explicit selection discards the forward branch; revisiting an entry does not.
@available(iOS 17.0, *)
@MainActor
struct PlayerPlaybackHistory {
    struct Entry {
        let video: Video
        let skipRecommendations: Bool
        let preservesPlaylistPosition: Bool
    }

    private static let maximumCount = 50
    private var entries: [Entry] = []
    private(set) var currentIndex = -1

    var count: Int { entries.count }
    var canMoveBackward: Bool { currentIndex > 0 }
    var hasForwardEntry: Bool { currentIndex + 1 < entries.count }

    mutating func record(_ entry: Entry) {
        if entries.indices.contains(currentIndex), entries[currentIndex].video.id == entry.video.id {
            return
        }
        if hasForwardEntry {
            entries.removeSubrange((currentIndex + 1)..<entries.count)
        }
        entries.append(entry)
        if entries.count > Self.maximumCount {
            entries.removeFirst(entries.count - Self.maximumCount)
        }
        currentIndex = entries.count - 1
    }

    mutating func updateCurrentVideo(_ video: Video) {
        guard entries.indices.contains(currentIndex),
              entries[currentIndex].video.id == video.id else { return }
        let entry = entries[currentIndex]
        entries[currentIndex] = Entry(
            video: video,
            skipRecommendations: entry.skipRecommendations,
            preservesPlaylistPosition: entry.preservesPlaylistPosition
        )
    }

    mutating func replaceCurrent(_ entry: Entry) {
        guard entries.indices.contains(currentIndex) else { return }
        entries[currentIndex] = entry
    }

    mutating func moveForward(where isAllowed: (Video) -> Bool) -> Entry? {
        guard hasForwardEntry else { return nil }
        for index in (currentIndex + 1)..<entries.count where isAllowed(entries[index].video) {
            currentIndex = index
            return entries[index]
        }
        return nil
    }

    mutating func moveBackward(where isAllowed: (Video) -> Bool) -> Entry? {
        guard canMoveBackward else { return nil }
        for index in stride(from: currentIndex - 1, through: 0, by: -1)
        where isAllowed(entries[index].video) {
            currentIndex = index
            return entries[index]
        }
        return nil
    }

    mutating func reset() {
        entries.removeAll()
        currentIndex = -1
    }
}
