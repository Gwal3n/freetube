import Foundation
import Observation

/// Best-effort sizes for the download picker. This is metadata-only and never resolves or saves a
/// signed stream URL; the download manager still chooses and validates the actual file.
@available(iOS 17.0, *)
@MainActor
@Observable
final class DownloadOptionsViewModel {
    private(set) var estimatedBytes: [VideoQuality: Int64] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    @ObservationIgnored private let videoService: any VideoServicing

    init(videoService: (any VideoServicing)? = nil) {
        self.videoService = videoService ?? VideoService()
    }

    func loadEstimates(for video: Video) async {
        guard !hasLoaded else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        guard let info = try? await videoService.fetchInfo(id: video.id), !Task.isCancelled else { return }
        guard let duration = video.duration ?? info.video.duration,
              duration.isFinite, duration > 0 else { return }

        let audioBitrate = info.formats
            .filter(\.isAudioOnly)
            .compactMap(\.bitrate)
            .filter { $0 > 0 }
            .max()
        if let audioBitrate, let size = Self.bytes(bitrate: audioBitrate, duration: duration) {
            estimatedBytes[.audioOnly] = size
        }

        let videos = info.formats.filter { format in
            format.isVideoOnly && format.height != nil && (format.bitrate ?? 0) > 0
        }
        for quality in VideoQuality.allCases where quality != .audioOnly {
            guard let cap = quality.heightCap else { continue }
            let withinCap = videos.filter { ($0.height ?? .max) <= cap }
            let candidates: [VideoFormat]
            if withinCap.isEmpty, let lowestHeight = videos.compactMap(\.height).min() {
                candidates = videos.filter { $0.height == lowestHeight }
            } else {
                candidates = withinCap
            }
            guard let selected = candidates.max(by: {
                if $0.height != $1.height { return ($0.height ?? 0) < ($1.height ?? 0) }
                return ($0.bitrate ?? 0) < ($1.bitrate ?? 0)
            }), let videoBitrate = selected.bitrate else { continue }
            let combined = videoBitrate + (audioBitrate ?? 0)
            if let size = Self.bytes(bitrate: combined, duration: duration) {
                estimatedBytes[quality] = size
            }
        }
    }

    private static func bytes(bitrate: Int, duration: TimeInterval) -> Int64? {
        let value = Double(bitrate) * duration / 8
        guard value.isFinite, value > 0, value < Double(Int64.max) else { return nil }
        return Int64(value)
    }
}
