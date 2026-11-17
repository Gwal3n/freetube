import Foundation
import Observation

/// Best-effort sizes for the download picker. Metadata only — never resolves or stores stream URLs.
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

    static func prefetch(for video: Video) {
        guard Self.cache[video.id] == nil else { return }
        _ = Self.startFetch(video, videoService: VideoService())
    }

    func loadEstimates(for video: Video) async {
        if let cached = Self.cache[video.id] {
            estimatedBytes = cached
            hasLoaded = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        await Self.startFetch(video, videoService: videoService).value
        if let cached = Self.cache[video.id] {
            estimatedBytes = cached
        }
    }

    @discardableResult
    private static func startFetch(
        _ video: Video,
        videoService: any VideoServicing
    ) -> Task<Void, Never> {
        if let existing = inFlight[video.id] { return existing }
        let task = Task { @MainActor in
            defer { inFlight[video.id] = nil }
            guard let entry = await fetchEstimates(for: video, videoService: videoService) else { return }
            cache[video.id] = entry
        }
        inFlight[video.id] = task
        return task
    }

    private static func fetchEstimates(
        for video: Video,
        videoService: any VideoServicing
    ) async -> [VideoQuality: Int64]? {
        guard let info = try? await videoService.fetchInfo(id: video.id), !Task.isCancelled else { return nil }
        guard let duration = video.duration ?? info.video.duration,
              duration.isFinite, duration > 0 else { return nil }

        var bytes: [VideoQuality: Int64] = [:]

        let audioFormats = info.formats.filter(\.isAudioOnly)
        let audioBitrate = audioFormats.compactMap(\.bitrate).filter { $0 > 0 }.max()
        if let audioBitrate, let size = Self.bytes(bitrate: audioBitrate, duration: duration) {
            bytes[.audioOnly] = size
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
                bytes[quality] = size
            }
        }

        return bytes
    }

    private static func bytes(bitrate: Int, duration: TimeInterval) -> Int64? {
        let value = Double(bitrate) * duration / 8
        guard value.isFinite, value > 0, value < Double(Int64.max) else { return nil }
        return Int64(value)
    }

    @ObservationIgnored private static var cache: [String: [VideoQuality: Int64]] = [:]
    @ObservationIgnored private static var inFlight: [String: Task<Void, Never>] = [:]
}
