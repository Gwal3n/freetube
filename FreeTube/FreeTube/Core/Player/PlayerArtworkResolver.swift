import Foundation
import Kingfisher
import UIKit

/// Finds playback artwork in memory, downloaded metadata, then the image cache/network.
/// The caller owns session validation before accepting an asynchronous image.
@available(iOS 17.0, *)
enum PlayerArtworkResolver {
    static func immediateArtwork(for video: Video) -> (image: UIImage?, needsNetworkLookup: Bool) {
        if let url = video.thumbnailURL,
           let cached = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey) {
            return (cached, false)
        }
        if let data = DownloadsStore.shared.thumbnail(forVideoID: video.id) {
            return (UIImage(data: data), true)
        }
        return (nil, true)
    }

    static func retrieveArtwork(for video: Video, completion: @escaping (UIImage) -> Void) {
        guard let url = video.thumbnailURL else { return }
        KingfisherManager.shared.retrieveImage(with: url) { result in
            guard case .success(let value) = result else { return }
            completion(value.image)
        }
    }
}
