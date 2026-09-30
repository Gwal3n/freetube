import Foundation

enum LocalPlaylistAddError: LocalizedError {
    case invalidVideoLink
    case alreadySaved
    case videoUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidVideoLink:
            return "Enter a YouTube video link or an 11-character video ID."
        case .alreadySaved:
            return "This video is already in the playlist."
        case .videoUnavailable:
            return "Video information is unavailable. Please try again later."
        }
    }
}
