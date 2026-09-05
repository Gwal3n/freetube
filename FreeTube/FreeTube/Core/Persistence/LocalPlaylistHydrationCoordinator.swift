import Foundation

@available(iOS 17.0, *)
actor LocalPlaylistHydrationCoordinator {
    static let shared = LocalPlaylistHydrationCoordinator()

    private var worker: Task<Void, Never>?
    private let service = LocalPlaylistService()

    func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task(priority: .utility) {
            await service.prepareLegacyImports()
            while !Task.isCancelled {
                let playlists = await service.playlistsAwaitingMetadata()
                guard !playlists.isEmpty else { break }
                for playlist in playlists {
                    guard !Task.isCancelled else { break }
                    await service.hydratePendingPlaylist(id: playlist.id)
                }
            }
            worker = nil
        }
    }
}
