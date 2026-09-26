import Foundation

/// Presentation-only branding. Originals in `Video` and local persistence are never rewritten.
nonisolated struct DeArrowBranding: Sendable {
    let title: String?
    let thumbnailData: Data?
    let thumbnailCacheKey: String?

    static let empty = DeArrowBranding(title: nil, thumbnailData: nil, thumbnailCacheKey: nil)
}
