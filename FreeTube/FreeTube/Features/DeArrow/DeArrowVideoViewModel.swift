import Foundation
import Observation

/// Per-row presentation state, isolated from playback and from the original `Video` value.
@available(iOS 17.0, *)
@MainActor
@Observable
final class DeArrowVideoViewModel {
    private var videoID: String?
    private var branding = DeArrowBranding.empty
    private var replaceTitles = false
    private var replaceThumbnails = false
    private var randomFallback = true
    private let originals = DeArrowOriginalsStore.shared
    private let service: DeArrowService

    init(service: DeArrowService = .shared) {
        self.service = service
    }

    func load(video: Video, replaceTitles: Bool, replaceThumbnails: Bool, randomFallback: Bool) async {
        guard !Task.isCancelled else { return }
        if videoID != video.id || self.randomFallback != randomFallback { branding = .empty }
        videoID = video.id
        self.replaceTitles = replaceTitles
        self.replaceThumbnails = replaceThumbnails
        self.randomFallback = randomFallback
        guard replaceTitles || replaceThumbnails else { return }
        do {
            // Titles can arrive immediately, without waiting for thumbnail generation. The
            // service reuses this payload when the image phase starts, so this is one lookup.
            let result = try await service.fetchBranding(for: video, includeThumbnails: false, randomFallback: randomFallback)
            guard !Task.isCancelled, videoID == video.id else { return }
            branding = DeArrowBranding(title: result.title, thumbnailData: branding.thumbnailData,
                                      thumbnailCacheKey: branding.thumbnailCacheKey)
            if replaceThumbnails {
                let fullResult = try await service.fetchBranding(for: video, includeThumbnails: true, randomFallback: randomFallback)
                guard !Task.isCancelled, videoID == video.id else { return }
                branding = fullResult
            }
        } catch {
            // Missing/failed branding is expected and intentionally silent: keep YouTube's
            // originals, with no spinner, alert, or dependency on stream resolution.
        }
    }

    func title(for video: Video) -> String {
        guard videoID == video.id, replaceTitles, !showsOriginal(for: video),
              let title = branding.title else { return video.title }
        return title
    }

    func thumbnailData(for video: Video) -> Data? {
        guard videoID == video.id, replaceThumbnails, !showsOriginal(for: video) else { return nil }
        return branding.thumbnailData
    }

    func thumbnailCacheKey(for video: Video) -> String? {
        thumbnailData(for: video) == nil ? nil : branding.thumbnailCacheKey
    }

    func hasReplacement(for video: Video) -> Bool {
        videoID == video.id && ((replaceTitles && branding.title != nil && branding.title != video.title)
            || (replaceThumbnails && branding.thumbnailData != nil))
    }

    func showsOriginal(for video: Video) -> Bool { originals.videoIDs.contains(video.id) }
    func toggleOriginal(for video: Video) { originals.toggle(videoID: video.id) }
}
