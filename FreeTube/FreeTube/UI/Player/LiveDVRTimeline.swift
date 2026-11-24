import SwiftUI

/// A rolling HLS timeline. Its bounds come from AVPlayer's seekable range, not the indefinite
/// duration of a live item. The range is frozen while dragging so the handle follows the finger
/// even if the live edge advances before the gesture ends.
@available(iOS 17.0, *)
struct LiveDVRTimeline: View {
    var scrubberTint = PlayerScrubberTint()

    let elapsed: TimeInterval
    let previewElapsed: TimeInterval?
    let seekableRange: ClosedRange<TimeInterval>?
    let onSeek: (TimeInterval) -> Void
    let onGoLive: () -> Void

    @State private var dragTarget: TimeInterval?
    @State private var dragRange: ClosedRange<TimeInterval>?

    private var scrubberColor: Color { scrubberTint.color }

    var body: some View {
        if let range = dragRange ?? seekableRange, range.upperBound - range.lowerBound >= 30 {
            let position = dragTarget ?? previewElapsed ?? elapsed
            let behindLive = max(0, range.upperBound - position)
            let atLiveEdge = behindLive < 10
            // HLS playback naturally sits a few seconds behind the latest seekable sample.
            // Use the same live-edge threshold for the label and LIVE button so a return to
            // live does not visibly count down from -0:04 and restart on every playlist tick.
            let displayedOffset = atLiveEdge && dragTarget == nil && previewElapsed == nil
                ? 0 : behindLive
            let displayedPosition = displayedOffset == 0 && dragTarget == nil && previewElapsed == nil
                ? range.upperBound : position

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    // LIVE stays leading beside the delay clock. At the live edge the clock
                    // hides so only the label remains.
                    liveLabel(atLiveEdge: atLiveEdge)
                    if !atLiveEdge || dragTarget != nil || previewElapsed != nil {
                        Text(verbatim: formatOffset(displayedOffset))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2.weight(.semibold))

                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let progress = fraction(of: displayedPosition, in: range)
                    // The fill keeps showing actual playback; only the thumb follows a scrub.
                    let isScrubbing = dragTarget != nil || previewElapsed != nil
                    let playbackProgress = isScrubbing
                        ? fraction(of: range.upperBound - elapsed < 10 ? range.upperBound : elapsed, in: range)
                        : progress
                    let thumbSize: CGFloat = dragTarget != nil ? 18 : 14

                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28)).frame(height: 4)
                        Capsule().fill(scrubberColor).frame(width: width * playbackProgress, height: 4)
                        Circle()
                            .fill(scrubberColor)
                            .frame(width: thumbSize, height: thumbSize)
                            .offset(x: min(max(width * progress - thumbSize / 2, 0), width - thumbSize))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragRange == nil { dragRange = range }
                                dragTarget = time(at: value.location.x, width: width, in: dragRange ?? range)
                            }
                            .onEnded { value in
                                let target = time(at: value.location.x, width: width, in: dragRange ?? range)
                                dragTarget = nil
                                dragRange = nil
                                if (seekableRange?.upperBound ?? range.upperBound) - target < 10 {
                                    onGoLive()
                                } else {
                                    onSeek(target)
                                }
                            }
                    )
                }
                .frame(height: 24)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live playback position")
            .accessibilityValue(
                atLiveEdge
                    ? "At live edge"
                    : "\(formatOffset(displayedOffset)) behind live"
            )
            .accessibilityAdjustableAction { direction in
                let delta: TimeInterval = direction == .increment ? 10 : -10
                onSeek(min(max(elapsed + delta, range.lowerBound), range.upperBound))
            }
        } else {
            HStack(spacing: 6) {
                liveBadge
                Spacer()
            }
            .padding(.vertical, 6)
            .frame(height: 43, alignment: .top)
            .accessibilityLabel("Live broadcast")
        }
    }

    /// White LIVE text for contrast on the video; the dot alone turns red at the live edge.
    /// Avoid `.disabled` here — SwiftUI fades disabled controls, which washes out LIVE at the edge.
    private func liveLabel(atLiveEdge: Bool) -> some View {
        Button {
            guard !atLiveEdge else { return }
            onGoLive()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(atLiveEdge ? Color.red : Color.white.opacity(0.85))
                    .frame(width: 5, height: 5)
                Text("LIVE")
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, Rectangle().inset(by: -10))
        .allowsHitTesting(!atLiveEdge)
        .accessibilityLabel(atLiveEdge ? "At live edge" : "Return to live")
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func fraction(of time: TimeInterval, in range: ClosedRange<TimeInterval>) -> CGFloat {
        CGFloat(min(max((time - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1))
    }

    private func time(at x: CGFloat, width: CGFloat, in range: ClosedRange<TimeInterval>) -> TimeInterval {
        range.lowerBound + Double(min(max(x / width, 0), 1)) * (range.upperBound - range.lowerBound)
    }

    private func formatOffset(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 { return String(format: "-%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "-%d:%02d", minutes, remainder)
    }
}
