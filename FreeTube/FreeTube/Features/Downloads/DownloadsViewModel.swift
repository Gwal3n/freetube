import Foundation
import Observation

/// Tiny façade around `DownloadManager` so the view stays declarative. `DownloadManager`
/// is itself `@Observable`, so the view reads `manager.activeTasks` directly — this
/// view-model only owns the error toast state and the cancel action.
@available(iOS 17.0, *)
@Observable
@MainActor
final class DownloadsViewModel {
    var errorState: ErrorState?
    private(set) var isSavingToPhotos = false

    let manager: DownloadManager
    private let exportService: DownloadedVideoExportService

    init(
        manager: DownloadManager? = nil,
        exportService: DownloadedVideoExportService? = nil
    ) {
        self.manager = manager ?? .shared
        self.exportService = exportService ?? DownloadedVideoExportService()
    }

    func saveToPhotos(fileURL: URL) async -> Bool {
        guard !isSavingToPhotos else { return false }
        isSavingToPhotos = true
        errorState = nil
        defer { isSavingToPhotos = false }
        do {
            try await exportService.saveToPhotos(fileURL: fileURL)
            return true
        } catch {
            errorState = ErrorState(from: error)
            return false
        }
    }

    /// Cancel a transfer-queue row by its download task ID.
    func cancel(_ snapshot: DownloadTaskSnapshot) {
        manager.cancel(taskID: snapshot.id)
    }
}
