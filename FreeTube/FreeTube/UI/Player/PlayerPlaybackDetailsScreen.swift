import AVFoundation
import SwiftUI

/// On-demand AVPlayer diagnostics. No signed playback URLs or account data are displayed.
@available(iOS 17.0, *)
@MainActor
struct PlayerPlaybackDetailsScreen: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot = Snapshot()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    detail("Reported quality", snapshot.quality)
                    detail("Picture size", snapshot.pictureSize)
                    detail("Preferred maximum", snapshot.maximum)
                } header: {
                    Text("Picture")
                } footer: {
                    Text("AVPlayer reports the picture size. It may not identify the exact HLS rendition currently being downloaded.")
                }

                Section("Playback") {
                    detail("Source", snapshot.source)
                    detail("State", snapshot.state)
                    detail("Selected speed", snapshot.selectedSpeed)
                    detail("Player rate", snapshot.playerRate)
                    detail("Buffered ahead", snapshot.bufferedAhead)
                }

                Section {
                    detail("Advertised bitrate", snapshot.advertisedBitrate)
                    detail("Average video bitrate", snapshot.videoBitrate)
                    detail("Average audio bitrate", snapshot.audioBitrate)
                    detail("Observed throughput", snapshot.observedThroughput)
                    detail("Dropped video frames", snapshot.droppedFrames)
                    detail("Playback stalls", snapshot.stalls)
                } header: {
                    Text("Stream and network")
                } footer: {
                    Text("Bitrates and throughput come from AVPlayer's access log. Missing values are shown as a dash.")
                }
            }
            .navigationTitle("Playback details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: player.playbackSessionID) {
            while !Task.isCancelled {
                snapshot = Snapshot.capture(from: player)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    @MainActor
    private struct Snapshot {
        var quality = "—"
        var pictureSize = "—"
        var maximum = "—"
        var source = "—"
        var state = "—"
        var selectedSpeed = "—"
        var playerRate = "—"
        var bufferedAhead = "—"
        var advertisedBitrate = "—"
        var videoBitrate = "—"
        var audioBitrate = "—"
        var observedThroughput = "—"
        var droppedFrames = "—"
        var stalls = "—"

        static func capture(from player: PlayerStateManager) -> Self {
            var result = Self()
            let size = player.videoPresentationSize
            result.quality = player.isAudioOnly
                ? String(localized: "Audio only")
                : VideoQuality.reportedPictureLabel(for: size) ?? "—"
            if VideoQuality.reportedPictureLabel(for: size) != nil {
                result.pictureSize = "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
            }
            result.maximum = player.playbackQuality.displayName
            result.source = player.acceptedStreamStrategy?.rawValue ?? String(localized: "Preparing")
            result.selectedSpeed = String(format: "%.2f×", player.effectivePlaybackRate)
            result.playerRate = String(format: "%.2f×", Double(player.player.rate))
            switch player.player.timeControlStatus {
            case .paused: result.state = String(localized: "Paused")
            case .waitingToPlayAtSpecifiedRate: result.state = String(localized: "Waiting")
            case .playing: result.state = String(localized: "Playing")
            @unknown default: result.state = "—"
            }
            if let range = player.bufferedRanges.first(where: { $0.contains(player.elapsed) }),
               range.upperBound.isFinite {
                result.bufferedAhead = String(format: "%.1f s", max(0, range.upperBound - player.elapsed))
            }
            if let event = player.player.currentItem?.accessLog()?.events.last {
                result.advertisedBitrate = bitrate(event.indicatedBitrate)
                result.videoBitrate = bitrate(event.averageVideoBitrate)
                result.audioBitrate = bitrate(event.averageAudioBitrate)
                result.observedThroughput = bitrate(event.observedBitrate)
                result.droppedFrames = String(event.numberOfDroppedVideoFrames)
                result.stalls = String(event.numberOfStalls)
            }
            return result
        }

        private static func bitrate(_ bitsPerSecond: Double) -> String {
            guard bitsPerSecond.isFinite, bitsPerSecond > 0 else { return "—" }
            if bitsPerSecond >= 1_000_000 {
                return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000)
            }
            return String(format: "%.0f kbps", bitsPerSecond / 1_000)
        }
    }
}
