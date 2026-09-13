import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class AccountViewModel {
    private(set) var info: AccountInfo?
    private(set) var isLoading: Bool = false
    var errorState: ErrorState?

    private let service: any AccountServicing
    private let session: SessionManager

    init(
        service: any AccountServicing = AccountService(),
        session: SessionManager = .shared
    ) {
        self.service = service
        self.session = session
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedInfo = try await service.fetchAccountInfo()
            guard !Task.isCancelled else { return }
            info = loadedInfo
        } catch is CancellationError {
            return
        } catch YouTubeServiceError.notAuthenticated {
            guard !Task.isCancelled else { return }
            info = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorState = ErrorState(from: error)
        }
    }

    func signOut() async {
        await session.signOut()
        await LoginCoordinator.clearWebData()
        info = nil
    }
}
