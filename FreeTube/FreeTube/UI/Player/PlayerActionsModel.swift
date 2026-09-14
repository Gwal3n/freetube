import Foundation
import Observation

/// Coordinates state behind the player's action row while sheet presentation remains attached to
/// `FullScreenPlayer`. This keeps download and local-playlist bookkeeping out of the player layout.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerActionsModel {
    private(set) var isSavedToPersonalPlaylist = false
    var downloadError: ErrorState?

    private let downloads: DownloadManager
    private let playlists: LocalPlaylistService
    private var membershipVideoID: String?

    init() {
        downloads = .shared
        playlists = LocalPlaylistService()
    }

    func refreshPlaylistMembership(for videoID: String?) async {
        membershipVideoID = videoID
        guard let videoID else {
            isSavedToPersonalPlaylist = false
            return
        }

        let isSaved = await playlists.isInPersonalPlaylist(videoID: videoID)
        guard membershipVideoID == videoID else { return }
        isSavedToPersonalPlaylist = isSaved
    }

    func downloadedFile(for videoID: String) -> URL? {
        downloads.localFile(for: videoID)
    }

    func downloadState(
        for videoID: String,
        downloadedFileURL: URL?
    ) -> PlayerDownloadPresentationState {
        if downloadedFileURL != nil { return .downloaded }
        if downloads.activeTasks.contains(where: { snapshot in
            guard snapshot.videoID == videoID else { return false }
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }) {
            return .downloading
        }
        return .available
    }

    func startDownload(_ video: Video) {
        let quality = UserPreferences().preferredQuality
        Task {
            do {
                _ = try await downloads.ensureDownloaded(video: video, quality: quality)
            } catch {
                downloadError = ErrorState(from: error)
            }
        }
    }
}
