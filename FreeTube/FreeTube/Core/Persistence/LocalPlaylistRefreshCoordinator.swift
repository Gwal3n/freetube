import Foundation

/// Owns explicit playlist metadata refreshes independently of any Library screen. A job keeps
/// running after navigation away, and AppEnvironment restarts unfinished work on a new launch.
@available(iOS 17.0, *)
actor LocalPlaylistRefreshCoordinator {
    static let shared = LocalPlaylistRefreshCoordinator()

    private var worker: Task<Void, Never>?
    private let service = LocalPlaylistService()

    func schedule(playlistID: String) async -> Bool {
        let queued = await service.scheduleMetadataRefresh(id: playlistID)
        if queued { resumePending() }
        return queued
    }

    func resumePending() {
        guard worker == nil else { return }
        worker = Task(priority: .utility) {
            while !Task.isCancelled {
                let pending = await service.playlistsAwaitingMetadataRefresh()
                guard let playlistID = pending.first else { break }
                await service.refreshPendingMetadata(id: playlistID)
            }
            worker = nil
            // A new request can be queued after the final empty-list read but before this task
            // clears `worker`. Check once more so that request cannot be left waiting for relaunch.
            guard !Task.isCancelled else { return }
            let newlyPending = await service.playlistsAwaitingMetadataRefresh()
            if !newlyPending.isEmpty {
                resumePending()
            }
        }
    }
}
