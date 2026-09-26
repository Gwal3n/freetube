import Foundation
import Observation

@available(iOS 17.0, *)
@MainActor
@Observable
final class PlaylistActionsModel {
    private(set) var isSaved = false
    private(set) var isSaving = false
    private(set) var hasLoaded = false
    var errorState: ErrorState?
    private let service = LocalPlaylistService()

    func refresh(id: String) async {
        isSaved = await service.isRemoteSaved(id: id)
        hasLoaded = true
    }

    func toggleSave(_ playlist: Playlist) async {
        guard hasLoaded, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorState = nil
        if isSaved {
            await service.removeRemotePlaylist(id: playlist.id)
            isSaved = false
        } else {
            do {
                try await service.saveRemotePlaylist(playlist)
                isSaved = true
            } catch {
                errorState = ErrorState(from: error)
            }
        }
    }
}
