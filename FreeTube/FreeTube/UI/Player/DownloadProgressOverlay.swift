import SwiftUI

/// Overlay rendered on top of the player surface while a video isn't playing yet. Reads
/// `PlayerStateManager.loadState` and disappears once `.readyToPlay` flips on.
///
/// Two visual registers, because the two waits are nothing alike:
///
/// - **Startup (`.resolving` / `.buffering`)** — normally under three seconds and covered by
///   `PlayerArtworkBackdrop`'s thumbnail. All we add is a small spinner, with no scrim and no label:
///   dimming the artwork and captioning it "Preparing…" is exactly the "this app is loading" tell
///   the perception pass exists to remove.
/// - **`.downloading` / `.failed`** — the legacy yt-dlp fallback and hard errors, which can run for
///   minutes and genuinely need words. These keep the dimmed scrim, the label, and the determinate
///   bar, now reading over the thumbnail rather than over black.
@available(iOS 17.0, *)
struct DownloadProgressOverlay: View {
    let state: PlayerStateManager.LoadState

    var body: some View {
        switch state {
        case .resolving, .buffering:
            startupIndicator
        case .downloading(let progress, let phase):
            overlay(label: label(for: progress, phase: phase), progress: progress)
        case .failed(let message):
            overlay(label: message, progress: nil, error: true)
        case .idle, .readyToPlay:
            EmptyView()
        }
    }

    /// Unobtrusive "still working" hint over the artwork. `allowsHitTesting(false)` matters: this
    /// sits above `PlayerSurface`, and a hit-testable layer here would swallow taps meant for
    /// `AVPlayerViewController`'s controls.
    @ViewBuilder
    private var startupIndicator: some View {
        PlaybackActivityIndicator(size: 30, lineWidth: 3.5)
            .padding(12)
            .background(.black.opacity(0.58), in: Circle())
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    @ViewBuilder
    private func overlay(label: String, progress: Double?, error: Bool = false) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                if error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.3)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .frame(maxWidth: 220)
                        .padding(.horizontal, 24)
                }
            }
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
