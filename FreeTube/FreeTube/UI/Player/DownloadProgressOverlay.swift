import SwiftUI

/// Long-running transfer feedback and terminal playback errors over the artwork. Brief startup
/// waits use the transport overlay's small indicator instead, so this view never duplicates it.
@available(iOS 17.0, *)
struct DownloadProgressOverlay: View {
    let state: PlayerStateManager.LoadState
    let allowsRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .downloading(let progress, let phase):
            overlay(label: label(for: progress, phase: phase), progress: progress)
        case .failed(let message):
            overlay(label: message, progress: nil, error: true)
        case .idle, .resolving, .buffering, .readyToPlay:
            EmptyView()
        }
    }

    @ViewBuilder
    private func overlay(label: String, progress: Double?, error: Bool = false) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                if error {
                    Image(systemName: "play.slash")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                } else if progress == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                if error && allowsRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .controlSize(.regular)
                }
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Download progress")
                }
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    /// Phrasing rules:
    /// - "Downloading video 42%" / "Downloading audio 75%" when we know which stream is in flight
    /// - "Processing video…" between phases (yt-dlp switching from video → audio, or post-download mux)
    /// - "Downloading…" as a generic fallback
    private func label(for progress: Double?, phase: String?) -> String {
        guard let progress else { return "Processing video…" }
        let percent = Int(progress * 100)
        if let phase, phase == "video" || phase == "audio" {
            return "Downloading \(phase) \(percent)%"
        }
        return "Downloading \(percent)%"
    }
}

/// A crisp indeterminate ring shared by the expanded and mini players. Timeline-driven rotation
/// avoids lifecycle-sensitive repeat-forever animation state and pauses cleanly for Reduce Motion.
struct PlaybackActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let rotation = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 0.85) / 0.85 * 360
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Preparing video")
    }
}
