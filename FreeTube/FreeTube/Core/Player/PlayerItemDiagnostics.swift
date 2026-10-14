import AVFoundation
import CoreMedia
import Foundation

/// URL-free AVPlayer item diagnostics. Throttling lives here so frequent HLS notifications do not
/// schedule a file-log write on every segment or playback-rate change.
@available(iOS 17.0, *)
@MainActor
final class PlayerItemDiagnostics {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlayerStateManager")
    private var lastAccessLogAt = Date.distantPast
    private var lastLiveDVRLogAt = Date.distantPast

    func reset() {
        lastAccessLogAt = .distantPast
        lastLiveDVRLogAt = .distantPast
    }

    func logAccessIfNeeded(for item: AVPlayerItem) {
        let now = Date()
        guard now.timeIntervalSince(lastAccessLogAt) >= 5 else { return }
        lastAccessLogAt = now
        guard let entry = item.accessLog()?.events.last else { return }
        // Access-log URIs and server addresses may contain signed playback credentials.
        log.info("AVPlayerItem access-log: indicatedBitrate=\(entry.indicatedBitrate, privacy: .public) indicatedAverageBitrate=\(entry.indicatedAverageBitrate, privacy: .public) averageAudioBitrate=\(entry.averageAudioBitrate, privacy: .public) averageVideoBitrate=\(entry.averageVideoBitrate, privacy: .public) observedBitrate=\(entry.observedBitrate, privacy: .public) switchBitrate=\(entry.switchBitrate, privacy: .public) downloadedDuration=\(entry.segmentsDownloadedDuration, privacy: .public)s watchedDuration=\(entry.durationWatched, privacy: .public)s droppedFrames=\(entry.numberOfDroppedVideoFrames, privacy: .public) stalls=\(entry.numberOfStalls, privacy: .public)")
    }

    /// Compare source rendition quality with the active audio route without recording route names
    /// or signed stream URLs.
    func logAudio(for item: AVPlayerItem, allowsMixing: Bool) {
        let session = AVAudioSession.sharedInstance()
        let outputTypes = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        log.info("Audio session: category=\(session.category.rawValue, privacy: .public) mode=\(session.mode.rawValue, privacy: .public) route=\(outputTypes, privacy: .public) sampleRate=\(session.sampleRate, privacy: .public)Hz channels=\(session.outputNumberOfChannels, privacy: .public) mixing=\(allowsMixing, privacy: .public)")

        Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard !tracks.isEmpty else {
                    self.log.notice("Audio diagnostics: AVPlayer asset exposes no audio track")
                    return
                }
                for (index, track) in tracks.enumerated() {
                    async let dataRate = track.load(.estimatedDataRate)
                    async let descriptions = track.load(.formatDescriptions)
                    let (estimatedDataRate, formatDescriptions) = try await (dataRate, descriptions)
                    if formatDescriptions.isEmpty {
                        self.log.info("Audio track[\(index, privacy: .public)]: estimatedDataRate=\(estimatedDataRate, privacy: .public)bps formatDescriptions=0")
                    }
                    for description in formatDescriptions {
                        let codec = Self.fourCCString(CMFormatDescriptionGetMediaSubType(description))
                        if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                            self.log.info("Audio track[\(index, privacy: .public)]: codec=\(codec, privacy: .public) estimatedDataRate=\(estimatedDataRate, privacy: .public)bps sampleRate=\(stream.mSampleRate, privacy: .public)Hz channels=\(stream.mChannelsPerFrame, privacy: .public) bitsPerChannel=\(stream.mBitsPerChannel, privacy: .public)")
                        } else {
                            self.log.info("Audio track[\(index, privacy: .public)]: codec=\(codec, privacy: .public) estimatedDataRate=\(estimatedDataRate, privacy: .public)bps streamDescription=unavailable")
                        }
                    }
                }
            } catch {
                self.log.notice("Audio diagnostics failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func logLiveDVRIfNeeded(for item: AVPlayerItem, videoID: String) {
        let now = Date()
        guard now.timeIntervalSince(lastLiveDVRLogAt) >= 15 else { return }
        lastLiveDVRLogAt = now

        let ranges = item.seekableTimeRanges.compactMap { value -> (start: Double, end: Double)? in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return (start, end)
        }
        guard let firstStart = ranges.map({ $0.start }).min(),
              let lastEnd = ranges.map({ $0.end }).max() else {
            log.info("Live DVR range video=\(videoID, privacy: .public) count=0")
            return
        }
        let playableSeconds = ranges.reduce(0) { $0 + $1.end - $1.start }
        let playhead = item.currentTime().seconds
        let behindLive = playhead.isFinite ? max(0, lastEnd - playhead) : 0
        log.info("Live DVR range video=\(videoID, privacy: .public) count=\(ranges.count, privacy: .public) span=\(lastEnd - firstStart, privacy: .public)s playable=\(playableSeconds, privacy: .public)s behindLive=\(behindLive, privacy: .public)s")
    }

    private nonisolated static func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}
