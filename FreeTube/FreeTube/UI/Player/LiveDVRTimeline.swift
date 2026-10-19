import SwiftUI

/// A rolling HLS timeline. Its bounds come from AVPlayer's seekable range, not the indefinite
/// duration of a live item. The range is frozen while dragging so the handle follows the finger
/// even if the live edge advances before the gesture ends.
@available(iOS 17.0, *)
struct LiveDVRTimeline: View {
    @AppStorage("playerScrubberColorMode") private var scrubberColorModeRaw = PlayerScrubberColorMode.standard.rawValue
    @AppStorage("playerScrubberCustomHex") private var scrubberCustomHex = "#FF0000"

    let elapsed: TimeInterval
    let previewElapsed: TimeInterval?
    let seekableRange: ClosedRange<TimeInterval>?
    let onSeek: (TimeInterval) -> Void
    let onGoLive: () -> Void

    @State private var dragTarget: TimeInterval?
    @State private var dragRange: ClosedRange<TimeInterval>?

    private var scrubberColor: Color {
        (PlayerScrubberColorMode(rawValue: scrubberColorModeRaw) ?? .standard)
            .color(customHex: scrubberCustomHex)
    }

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
                HStack {
                    Text(verbatim: formatOffset(displayedOffset))
                        .monospacedDigit()
                    Spacer()
                    Button(action: onGoLive) {
                        HStack(spacing: 5) {
                            Circle().frame(width: 5, height: 5)
                            Text("LIVE")
                        }
                        .foregroundStyle(atLiveEdge ? Color.red : Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(.interaction, Rectangle().inset(by: -10))
                    .disabled(atLiveEdge)
                    .accessibilityLabel(atLiveEdge ? "At live edge" : "Return to live")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)

                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let progress = fraction(of: displayedPosition, in: range)

                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28)).frame(height: 4)
                        Capsule().fill(scrubberColor).frame(width: width * progress, height: 4)
                        Circle()
                            .fill(scrubberColor)
                            .frame(width: 14, height: 14)
                            .offset(x: min(max(width * progress - 7, 0), width - 14))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
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
            .accessibilityValue("\(formatOffset(displayedOffset)) behind live")
            .accessibilityAdjustableAction { direction in
                let delta: TimeInterval = direction == .increment ? 10 : -10
                onSeek(min(max(elapsed + delta, range.lowerBound), range.upperBound))
            }
        } else {
            HStack {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: RoundedRectangle(cornerRadius: 3))
                Spacer()
            }
            .padding(.vertical, 6)
            .frame(height: 43, alignment: .top)
            .accessibilityLabel("Live broadcast")
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
