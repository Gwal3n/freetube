import Foundation

enum YouTubeServiceError: Error, Sendable {
    case notAuthenticated
    case rateLimited
    case videoUnavailable
    case streamExtractionFailed
    case cookieExpired
    case network(Error)
    case decoding(Error)
    case unknown(Error)
}

extension YouTubeServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "This content isn’t available without a YouTube account."
        case .rateLimited: return "YouTube is rate-limiting requests. Try again in a moment."
        case .videoUnavailable: return "This video is unavailable."
        case .streamExtractionFailed:
            return "The video stream couldn’t be loaded. Please try again."
        case .cookieExpired:
            return "The playback session expired. Try loading the video again."
        case .network:
            return "YouTube couldn’t be reached. Check your connection and try again."
        case .decoding:
            return "YouTube returned an unexpected response. Please try again."
        case .unknown:
            return "The YouTube request couldn’t be completed. Please try again."
        }
    }
}
