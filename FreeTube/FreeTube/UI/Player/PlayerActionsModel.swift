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
    var pendingDownloadDeletion: Video?
    private(set) var requestedDownloadIDs: Set<String> = []
    @ObservationIgnored private var downloadRequests: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var downloadRequestTokens: [String: UUID] = [:]

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
        if requestedDownloadIDs.contains(videoID) { return .downloading }
        if downloads.activeTasks.contains(where: { snapshot in
            guard snapshot.videoID == videoID else { return false }
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }) {
            return .downloading
        }
        if downloadedFileURL != nil { return .downloaded }
        return .available
    }

    func startDownload(_ video: Video) {
        guard !requestedDownloadIDs.contains(video.id) else { return }
        downloadError = nil
        let quality = UserPreferences().preferredQuality
        let token = UUID()
        downloadRequestTokens[video.id] = token
        requestedDownloadIDs.insert(video.id)
        downloadRequests[video.id] = Task {
            defer {
                if downloadRequestTokens[video.id] == token {
                    downloadRequestTokens[video.id] = nil
                    downloadRequests[video.id] = nil
                    requestedDownloadIDs.remove(video.id)
                }
            }
            guard !Task.isCancelled else { return }
            do {
                _ = try await downloads.ensureDownloaded(video: video, quality: quality)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      downloadRequestTokens[video.id] == token else { return }
                downloadError = ErrorState(from: error)
            }
        }
    }

    func handleDownloadTap(_ video: Video) {
        // A transfer may have written its destination before validation finishes. Do not
        // mistake that partial file for a completed download eligible for deletion.
        if downloadState(for: video.id, downloadedFileURL: nil) == .downloading {
            downloadRequests[video.id]?.cancel()
            for snapshot in downloads.activeTasks where snapshot.videoID == video.id {
                switch snapshot.state {
                case .queued, .downloading, .paused: downloads.cancel(taskID: snapshot.id)
                case .completed, .failed: break
                }
            }
            return
        }
        if downloadedFile(for: video.id) != nil {
            pendingDownloadDeletion = video
            return
        }
        startDownload(video)
    }

    func confirmDownloadDeletion(_ video: Video) {
        pendingDownloadDeletion = nil
        guard let url = downloadedFile(for: video.id) else { return }
        DownloadsStore.shared.delete(at: url)
        if FileManager.default.fileExists(atPath: url.path) {
            downloadError = ErrorState(from: NSError(
                domain: "PlayerActions", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The downloaded file could not be deleted."]
            ))
        }
    }
}
