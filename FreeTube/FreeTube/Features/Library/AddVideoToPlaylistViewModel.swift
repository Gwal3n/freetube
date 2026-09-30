import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class AddVideoToPlaylistViewModel {
    var link = ""
    private(set) var isAdding = false
    var errorState: ErrorState?
    private let service: LocalPlaylistService

    init(service: LocalPlaylistService = LocalPlaylistService()) {
        self.service = service
    }

    func add(to playlistID: String) async -> Bool {
        guard !isAdding else { return false }
        isAdding = true
        errorState = nil
        defer { isAdding = false }
        do {
            try await service.addVideo(from: link, to: playlistID)
            return true
        } catch {
            errorState = ErrorState(from: error)
            return false
        }
    }
}
