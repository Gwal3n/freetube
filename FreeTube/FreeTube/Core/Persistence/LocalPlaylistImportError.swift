import Foundation

enum LocalPlaylistImportError: LocalizedError {
    case invalidCSV
    case noVideos

    var errorDescription: String? {
        switch self {
        case .invalidCSV:
            return "The CSV must contain a Video ID column."
        case .noVideos:
            return "No valid YouTube video IDs were found."
        }
    }
}
