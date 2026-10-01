import Foundation

enum DownloadedVideoExportError: LocalizedError {
    case fileMissing
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "The saved video file is no longer available."
        case .photosAccessDenied:
            return "Allow FreeTube to add videos in Settings to save this file to Photos."
        }
    }
}
