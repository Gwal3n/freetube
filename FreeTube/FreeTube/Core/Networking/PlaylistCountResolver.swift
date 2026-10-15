import Foundation

/// Resolves counts only when a playlist row omitted one. Reuses in-flight requests and limits
/// concurrent lookups so a search page cannot fan out dozens of playlist requests at once.
@available(iOS 17.0, *)
actor PlaylistCountResolver {
    static let shared = PlaylistCountResolver()

    private struct CacheEntry {
        let count: Int?
        let fetchedAt: Date
    }

    private let service: any PlaylistServicing
    private var cached: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<Int?, Never>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cacheGeneration = 0

    func clearCache() {
        cacheGeneration += 1
        cached.removeAll()
    }

    init(service: any PlaylistServicing = PlaylistService()) {
        self.service = service
    }

    func count(for playlistID: String) async -> Int? {
        if let cached = cached[playlistID], Date.now.timeIntervalSince(cached.fetchedAt) < 900 {
            return cached.count
        }
        if let pending = inFlight[playlistID] { return await pending.value }

        let task = Task { await fetchCount(playlistID: playlistID) }
        let generation = cacheGeneration
        inFlight[playlistID] = task
        let count = await task.value
        inFlight[playlistID] = nil
        if generation == cacheGeneration {
            cached[playlistID] = CacheEntry(count: count, fetchedAt: .now)
        }
        return count
    }

    private func fetchCount(playlistID: String) async -> Int? {
        await acquireSlot()
        guard !Task.isCancelled else {
            releaseSlot()
            return nil
        }
        let details = try? await service.fetchPlaylist(id: playlistID)
        releaseSlot()
        guard let details else { return nil }
        if let count = details.playlist.videoCount { return count }
        return details.continuationToken == nil ? details.videos.count : nil
    }

    private func acquireSlot() async {
        if activeRequests < 2 {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
