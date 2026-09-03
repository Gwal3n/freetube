import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockTimeline: View {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let segments: [SponsorBlockSegment]
    let chapters: [VideoChapter]
    let onSeek: (TimeInterval) -> Void
    let onPreviewChanged: (TimeInterval?) -> Void

    @State private var dragTime: TimeInterval?

    private var displayedTime: TimeInterval { dragTime ?? elapsed }
    private var currentChapter: VideoChapter? {
        chapters.last { $0.startTime <= displayedTime }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Text(verbatim: format(displayedTime))
                if let currentChapter {
                    Menu {
                        ForEach(chapters) { chapter in
                            Button {
                                onSeek(chapter.startTime)
                            } label: {
                                if chapter.id == currentChapter.id {
                                    Label {
                                        Text(verbatim: chapterMenuTitle(chapter))
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                } else {
                                    Text(verbatim: chapterMenuTitle(chapter))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(verbatim: currentChapter.title)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: 190, alignment: .leading)
                    }
                    .accessibilityLabel("Current chapter, \(currentChapter.title)")
                }
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
                        let segmentWidth = width * fraction(for: segment.endTime - segment.startTime)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color(for: segment.category))
                            .frame(
                                width: segment.category == .highlight ? max(3, segmentWidth) : max(2, segmentWidth),
                                height: 4
                            )
                            .offset(x: width * fraction(for: segment.startTime))
                    }

                    // Fine gaps divide the shared progress track without competing visually with
                    // SponsorBlock's colored ranges. The first chapter starts at zero, so only
                    // later boundaries need a marker.
                    ForEach(chapters.filter { $0.startTime > 0 }) { chapter in
                        Rectangle()
                            .fill(.black.opacity(0.82))
                            .frame(width: 2, height: 4)
                            .offset(x: min(max(width * fraction(for: chapter.startTime) - 1, 0), width - 2))
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
                            let target = min(max(value.location.x / width, 0), 1) * duration
                            dragTime = target
                            onPreviewChanged(target)
                        }
                        .onEnded { value in
                            guard duration > 0 else { dragTime = nil; return }
                            let target = min(max(value.location.x / width, 0), 1) * duration
                            dragTime = nil
                            onPreviewChanged(nil)
                            onSeek(target)
                        }
                )
            }
            .frame(height: 24)
        }
        .accessibilityElement(children: chapters.isEmpty ? .ignore : .contain)
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
        case .highlight: return .purple
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

    private func chapterMenuTitle(_ chapter: VideoChapter) -> String {
        let timestamp = chapter.timeDescription ?? format(chapter.startTime)
        return "\(timestamp)  \(chapter.title)"
    }
}
