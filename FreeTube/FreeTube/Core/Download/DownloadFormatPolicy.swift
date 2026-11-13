import Foundation

/// Chooses usable direct formats when the native stream download cannot finish.
@available(iOS 17.0, *)
enum DownloadFormatPolicy {
    /// Highest-resolution progressive format within the user's quality limit.
    static func pickBestProgressive(formats: [VideoFormat], maxHeight: Int) -> VideoFormat? {
        formats
            .filter { $0.containsBothTracks && $0.url != nil }
            .filter { ($0.height ?? Int.max) <= maxHeight }
            .max { ($0.height ?? 0) < ($1.height ?? 0) }
    }

    /// Highest-resolution video-only format within the limit. Prefer MP4 for local playback.
    static func pickBestVideoOnly(formats: [VideoFormat], maxHeight: Int) -> VideoFormat? {
        let candidates = formats.filter { $0.isVideoOnly && $0.url != nil && ($0.height ?? Int.max) <= maxHeight }
        let mp4s = candidates.filter { $0.mimeType.lowercased().contains("mp4") }
        let pool = mp4s.isEmpty ? candidates : mp4s
        return pool.max { ($0.height ?? 0) < ($1.height ?? 0) }
    }

    /// Highest-bitrate audio-only format. Prefer M4A/MP4 for the local MP4 container.
    static func pickBestAudioOnly(formats: [VideoFormat]) -> VideoFormat? {
        let candidates = formats.filter { $0.isAudioOnly && $0.url != nil }
        let mp4s = candidates.filter {
            $0.mimeType.lowercased().contains("mp4") || $0.mimeType.lowercased().contains("m4a")
        }
        let pool = mp4s.isEmpty ? candidates : mp4s
        return pool.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    /// Next-best video-only URLs after a CDN rejection of `excluding`.
    static func alternateVideoOnlyURLs(
        formats: [VideoFormat],
        maxHeight: Int,
        excluding: URL
    ) -> [URL] {
        let candidates = formats.filter { $0.isVideoOnly && $0.url != nil && ($0.height ?? Int.max) <= maxHeight }
        let mp4s = candidates.filter { $0.mimeType.lowercased().contains("mp4") }
        let pool = (mp4s.isEmpty ? candidates : mp4s)
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        return pool.compactMap(\.url).filter { $0 != excluding }
    }

    /// Next-best audio-only URLs after a CDN rejection of `excluding`.
    static func alternateAudioOnlyURLs(formats: [VideoFormat], excluding: URL) -> [URL] {
        let candidates = formats.filter { $0.isAudioOnly && $0.url != nil }
        let mp4s = candidates.filter {
            $0.mimeType.lowercased().contains("mp4") || $0.mimeType.lowercased().contains("m4a")
        }
        let pool = (mp4s.isEmpty ? candidates : mp4s)
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        return pool.compactMap(\.url).filter { $0 != excluding }
    }

    static func targetHeight(for quality: VideoQuality) -> Int {
        let cap = quality.heightCap ?? 1080
        return cap > 0 ? cap : 1080
    }
}
