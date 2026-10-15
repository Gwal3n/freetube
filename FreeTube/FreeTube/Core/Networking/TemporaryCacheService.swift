import Foundation
import Kingfisher

/// Clears disposable caches only. Downloads and local library data are never touched.
@available(iOS 17.0, *)
@MainActor
enum TemporaryCacheService {
    /// On-disk cache usage only; recent metadata and signed stream URLs are memory-only.
    static func diskUsageBytes() async -> Int64? {
        guard let imageBytes = try? await ImageCache.default.diskStorageSize else { return nil }
        return Int64(clamping: imageBytes) + Int64(URLCache.shared.currentDiskUsage)
    }

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
