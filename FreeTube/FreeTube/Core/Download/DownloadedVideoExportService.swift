import Foundation
import Photos

/// Exports a completed local video without reading the entire file into memory.
@available(iOS 17.0, *)
@MainActor
final class DownloadedVideoExportService {
    func saveToPhotos(fileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DownloadedVideoExportError.fileMissing
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw DownloadedVideoExportError.photosAccessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: fileURL, options: nil)
        }
    }
}
