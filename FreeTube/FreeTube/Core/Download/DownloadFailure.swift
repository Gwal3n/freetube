import Foundation

/// User-facing download failures. Kept separate from playback `YouTubeServiceError` so a remux
/// or CDN 403 is not reported as a generic “stream couldn’t be loaded.”
@available(iOS 17.0, *)
enum DownloadFailure: Error, Sendable, Equatable {
    case remuxFailed
    case forbidden
    case noFormats
    case incompleteTransfer
    case validationFailed
    case unavailable

    /// Maps known download-path errors; unknown errors become `.unavailable`.
    static func wrapping(_ error: Error) -> DownloadFailure {
        if let failure = error as? DownloadFailure { return failure }
        if NativeHLSDownloadService.isMuxFailure(error) { return .remuxFailed }
        if NativeHLSDownloadService.isAuthorizationFailure(error) { return .forbidden }
        if let service = error as? YouTubeServiceError {
            switch service {
            case .streamExtractionFailed, .videoUnavailable: return .unavailable
            case .rateLimited: return .forbidden
            case .network, .decoding, .unknown: return .unavailable
            }
        }
        return .unavailable
    }
}

@available(iOS 17.0, *)
extension DownloadFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .remuxFailed:
            return "The download finished transferring but couldn’t be saved as a playable file. Please try again."
        case .forbidden:
            return "YouTube blocked the download. Please try again in a moment."
        case .noFormats:
            return "No downloadable formats were available for this video."
        case .incompleteTransfer:
            return "The download was incomplete. Please try again."
        case .validationFailed:
            return "The downloaded file wasn’t playable. Please try again."
        case .unavailable:
            return "This video couldn’t be downloaded. Please try again."
        }
    }
}

/// Which InnerTube client minted the signed media URLs — the CDN often requires a matching UA.
@available(iOS 17.0, *)
enum DownloadClientIdentity: Sendable {
    /// `TVHTML5_SIMPLY_EMBEDDED_PLAYER` (PlayStation UA in YouTubeKitClient).
    case tvHTML5
    /// iOS / WEB player.js formats from `VideoInfosWithDownloadFormatsResponse`.
    case web

    var userAgent: String {
        switch self {
        case .tvHTML5:
            return "Mozilla/5.0 (PlayStation; PlayStation 4/12.55) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15"
        case .web:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15"
        }
    }
}
