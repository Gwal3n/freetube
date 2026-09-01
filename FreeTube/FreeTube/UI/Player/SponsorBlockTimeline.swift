import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockTimeline: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let segments: [SponsorBlockSegment]
    let onSeek: (TimeInterval) -> Void

    @State private var dragTime: TimeInterval?

    private var displayedTime: TimeInterval { dragTime ?? elapsed }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(verbatim: format(displayedTime))
                Spacer()
                Text(verbatim: format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let progress = fraction(for: displayedTime)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.32)).frame(height: 4)
                    Capsule().fill(.red).frame(width: width * progress, height: 4)

                    ForEach(segments, id: \.id) { segment in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color(for: segment.category))
                            .frame(
                                width: max(2, width * fraction(for: segment.endTime - segment.startTime)),
                                height: 4
                            )
                            .offset(x: width * fraction(for: segment.startTime))
                    }

                    Circle()
                        .fill(.red)
                        .frame(width: 14, height: 14)
                        .offset(x: min(max(width * progress - 7, 0), width - 14))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragTime = min(max(value.location.x / width, 0), 1) * duration
                        }
                        .onEnded { value in
                            guard duration > 0 else { dragTime = nil; return }
                            let target = min(max(value.location.x / width, 0), 1) * duration
                            dragTime = nil
                            onSeek(target)
                        }
                )
            }
            .frame(height: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(format(displayedTime)) of \(format(duration))")
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? 10 : -10
            onSeek(min(max(elapsed + delta, 0), duration))
        }
    }

    private func fraction(for time: TimeInterval) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1))
    }

    private func color(for category: SponsorBlockCategory) -> Color {
        switch category {
        case .sponsor: return .green
        case .selfPromotion: return .yellow
        case .interaction: return .pink
        case .intro: return .cyan
        case .outro: return .blue
        }
    }

    private func format(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
