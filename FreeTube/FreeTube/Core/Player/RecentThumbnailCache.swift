import UIKit

/// Thumbnails the browsing UI has just drawn, keyed by video ID. Kingfisher keeps only the
/// downsampled variant in memory (the original goes to disk), so a cold-launch tap found no
/// artwork for the player to launch from and briefly showed black.
@MainActor
final class RecentThumbnailCache {
    static let shared = RecentThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }()

    func store(_ image: UIImage, for videoID: String) {
        cache.setObject(image, forKey: videoID as NSString)
    }

    func image(for videoID: String) -> UIImage? {
        cache.object(forKey: videoID as NSString)
    }
}
