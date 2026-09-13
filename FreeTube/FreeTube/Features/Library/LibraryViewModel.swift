import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class LibraryViewModel {
    private(set) var library: AccountLibrary?
    private(set) var isLoading: Bool = false
    var errorState: ErrorState?

    private let service: any AccountServicing

    init(service: any AccountServicing = AccountService()) {
        self.service = service
    }

    /// Drops cached library data. Called on sign-out so the next sign-in starts fresh and the
    /// menu's data-driven destinations (Playlists, Your videos) don't keep showing stale entries.
    func clear() {
        library = nil
        errorState = nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedLibrary = try await service.fetchLibrary()
            guard !Task.isCancelled else { return }
            library = loadedLibrary
        } catch is CancellationError {
            return
        } catch YouTubeServiceError.notAuthenticated {
            guard !Task.isCancelled else { return }
            // No cookies / signed-out — the library menu degrades to "sign in" prompts and
            // shouldn't surface a toast for this expected state.
            library = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorState = ErrorState(from: error)
        }
    }
}
