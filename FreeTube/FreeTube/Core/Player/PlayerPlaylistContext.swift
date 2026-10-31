import Foundation
import OSLog

/// Owns the active playlist identity and its network continuation.
/// Queue playback and History updates remain with PlayerStateManager.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerPlaylistContext {
    private let queue: QueueManager
    private let service: any PlaylistServicing
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")
    private var continuationToken: String?

    private(set) var playlist: Playlist?
    private(set) var origin: PlaylistPlaybackOrigin?
    private(set) var isLoadingMore = false
    var canLoadMore: Bool { playlist != nil && continuationToken != nil }

    init(queue: QueueManager, service: any PlaylistServicing) {
        self.queue = queue
        self.service = service
    }

    func begin(_ playlist: Playlist, origin: PlaylistPlaybackOrigin, continuationToken: String?) {
        self.playlist = playlist
        self.origin = origin
        self.continuationToken = continuationToken
    }

    func clear() {
        playlist = nil
        origin = nil
        continuationToken = nil
        isLoadingMore = false
    }

    func loadMore() async {
        guard let token = continuationToken, !isLoadingMore else { return }
        let playlistID = playlist?.id
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.fetchMore(continuation: token)
            guard playlist?.id == playlistID else { return }
            let existing = Set(queue.items.map(\.id))
            queue.append(contentsOf: page.videos.filter {
                !existing.contains($0.id) && !VideoBlocklist.shared.blocks($0)
            })
            continuationToken = page.continuationToken
        } catch {
            log.notice("Playlist continuation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
