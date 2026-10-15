import Foundation
import Kingfisher

/// Clears disposable caches only. Downloads and local library data are never touched.
@available(iOS 17.0, *)
@MainActor
enum TemporaryCacheService {
    static func clearRecentVideoContent() {
        VideoContentPrefetchStore.shared.clearCache()
    }

    static func clearAll(player: PlayerStateManager) async {
        clearRecentVideoContent()
        player.clearSponsorBlockCache()
        await StreamURLCache.shared.purge()
        await DeArrowService.shared.clearCache()
        await PlaylistCountResolver.shared.clearCache()
        ImageCache.default.clearMemoryCache()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageCache.default.clearDiskCache {
                continuation.resume()
            }
        }
        URLCache.shared.removeAllCachedResponses()
    }
}
