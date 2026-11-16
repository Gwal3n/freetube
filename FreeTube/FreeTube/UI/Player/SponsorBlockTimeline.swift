import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockTimeline: View {
    var scrubberTint = PlayerScrubberTint()
    @AppStorage("sponsorBlockColorOverridesJSON") private var sponsorBlockColorOverridesJSON = "{}"
    @AppStorage("sponsorBlockShowFullVideoSeekStripe") private var showFullVideoSeekStripe = false
    @AppStorage("scrubberChapterHighlight") private var highlightsScrubbedChapter = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let elapsed: TimeInterval
    let previewElapsed: TimeInterval?
    let duration: TimeInterval
    let bufferedRanges: [ClosedRange<TimeInterval>]
    let isLive: Bool
    let segments: [SponsorBlockSegment]
    let chapters: [VideoChapter]
    let onSeek: (TimeInterval) -> Void
    let onPreviewChanged: (TimeInterval?) -> Void
    let onShowChapters: () -> Void

    @State private var dragTime: TimeInterval?
    @State private var isPreviewingDrag = false
    @State private var scrubChapterID: VideoChapter.ID?
    @State private var chapterHapticTrigger = 0

    /// Where the thumb, time label, and chapter label point. While scrubbing this is the target;
    /// the progress fill keeps showing actual playback until the seek is committed.
    private var displayedTime: TimeInterval { dragTime ?? previewElapsed ?? elapsed }
    private var isScrubbing: Bool { dragTime != nil || previewElapsed != nil }
    private var currentChapter: VideoChapter? {
        // Match chapter-list highlighting: tolerate brief AVPlayer undershoot after a seek.
        chapters.last { $0.startTime <= displayedTime + 0.35 }
    }

    private static let trackHeight: CGFloat = 4
    private static let highlightedTrackHeight: CGFloat = 8

    /// The chapter under the thumb while scrubbing, enlarged when that preference is on.
    private var highlightedChapterRange: ClosedRange<TimeInterval>? {
        guard highlightsScrubbedChapter, isScrubbing, duration > 0,
              let index = chapters.lastIndex(where: { $0.startTime <= displayedTime }) else { return nil }
        let start = chapters[index].startTime
        let end = index + 1 < chapters.count ? chapters[index + 1].startTime : duration
        guard end > start else { return nil }
        return start...end
    }
    private var fullVideoLabel: SponsorBlockCategory? {
        SponsorBlockSegment.primaryFullVideoLabel(in: segments)
    }
    private var scrubberColor: Color { scrubberTint.color }

    var body: some View {
        if isLive, duration <= 0 {
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
            .accessibilityLabel("Live broadcast")
        } else {
        let sponsorColors = SponsorBlockColorPalette(json: sponsorBlockColorOverridesJSON)
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Text(verbatim: format(displayedTime))
                if let currentChapter {
                    Button(action: onShowChapters) {
                        HStack(spacing: 4) {
                            Text(verbatim: currentChapter.title)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        // A pill drawn outside the layout makes the label read as a control
                        // without changing the row height the seek preview aligns to.
                        .background {
                            Capsule()
                                .fill(.white.opacity(0.18))
                                .padding(.horizontal, -7)
                                .padding(.vertical, -3)
                        }
                        .frame(maxWidth: 190, alignment: .leading)
                    }
                    .padding(.leading, 6)
                    .contentShape(.interaction, Rectangle().inset(by: -10))
                    .accessibilityLabel("Current chapter, \(currentChapter.title)")
                }
                Spacer()
                Text(verbatim: format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let playbackProgress = fraction(for: elapsed)
                let thumbProgress = fraction(for: displayedTime)
                let highlight = highlightedChapterRange
                let gapWidth: CGFloat = chapters.count > 1
                    && width / CGFloat(chapters.count) < 24 ? 1 : 2
                let thumbSize: CGFloat = dragTime != nil ? 18 : 14

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: Self.trackHeight)
                    ForEach(bufferedRanges.indices, id: \.self) { index in
                        let range = bufferedRanges[index]
                        let start = fraction(for: range.lowerBound)
                        let end = fraction(for: range.upperBound)
                        Capsule()
                            .fill(.white.opacity(0.55))
                            .frame(width: width * max(0, end - start), height: Self.trackHeight)
                            .offset(x: width * start)
                    }
                    Capsule().fill(scrubberColor).frame(width: width * playbackProgress, height: Self.trackHeight)

                    if let highlight {
                        highlightedChapter(highlight, width: width, playbackProgress: playbackProgress)
                    }

                    // Full-video labels are annotations, never a seek target. Keep their slim
                    // stripe below the progress track so the playback position stays clear.
                    if showFullVideoSeekStripe, let fullVideoLabel {
                        Capsule()
                            .fill(sponsorColors.color(for: fullVideoLabel))
                            .frame(width: width, height: 2)
                            .offset(y: 5)
                    }

                    ForEach(segments.filter { $0.category != .chapter && !$0.isFullVideoLabel }, id: \.id) { segment in
                        let segmentWidth = width * fraction(for: segment.endTime - segment.startTime)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(sponsorColors.color(for: segment.category))
                            .frame(
                                width: segment.category == .highlight ? max(3, segmentWidth) : max(2, segmentWidth),
                                height: segmentHeight(segment, in: highlight)
                            )
                            .offset(x: width * fraction(for: segment.startTime))
                    }

                    // Fine gaps divide the shared progress track without competing visually with
                    // SponsorBlock's colored ranges. The first chapter starts at zero, so only
                    // later boundaries need a marker. Dense chapter lists get hairline gaps.
                    ForEach(chapters.filter { $0.startTime > 0 }) { chapter in
                        Rectangle()
                            .fill(.black)
                            .frame(width: gapWidth, height: Self.highlightedTrackHeight)
                            .offset(x: min(max(width * fraction(for: chapter.startTime) - gapWidth / 2, 0), width - gapWidth))
                            .blendMode(.destinationOut)
                    }

                    Circle()
                        .fill(scrubberColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: min(max(width * thumbProgress - thumbSize / 2, 0), width - thumbSize))
                }
                .compositingGroup()
                .frame(maxHeight: .infinity)
                .animation(reduceMotion ? nil : InterfaceMotion.quick, value: highlight)
                .animation(reduceMotion ? nil : InterfaceMotion.quick, value: thumbSize)
                // Extends touch below the track and into the row gap above it, but never over the
                // chapter label, whose own button must keep receiving taps.
                .contentShape(TimelineTouchShape())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            let target = min(max(value.location.x / width, 0), 1) * duration
                            dragTime = target
                            updateChapterHaptic(at: target)
                            // A tap still seeks on release, but a storyboard should appear only
                            // once the user deliberately drags the timeline.
                            if isPreviewingDrag || abs(value.translation.width) >= 3 {
                                isPreviewingDrag = true
                                onPreviewChanged(target)
                            }
                        }
                        .onEnded { value in
                            guard duration > 0 else {
                                dragTime = nil
                                isPreviewingDrag = false
                                scrubChapterID = nil
                                onPreviewChanged(nil)
                                return
                            }
                            let target = min(max(value.location.x / width, 0), 1) * duration
                            dragTime = nil
                            isPreviewingDrag = false
                            scrubChapterID = nil
                            onPreviewChanged(nil)
                            onSeek(target)
                        }
                )
            }
            .frame(height: 24)
        }
        .sensoryFeedback(.selection, trigger: chapterHapticTrigger)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(format(displayedTime)) of \(format(duration))")
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? 10 : -10
            onSeek(min(max(elapsed + delta, 0), duration))
        }
        }
    }

    /// Emits one light selection tick when a drag crosses a chapter boundary. The first chapter
    /// under the finger establishes the baseline silently so touching the scrubber does not buzz.
    private func updateChapterHaptic(at time: TimeInterval) {
        guard let chapterID = chapters.last(where: { $0.startTime <= time })?.id else { return }
        defer { scrubChapterID = chapterID }
        guard let previous = scrubChapterID, previous != chapterID else { return }
        chapterHapticTrigger &+= 1
    }

    /// The scrubbed chapter drawn taller and brighter over the normal track, keeping its own
    /// buffered and played portions.
    @ViewBuilder
    private func highlightedChapter(
        _ range: ClosedRange<TimeInterval>,
        width: CGFloat,
        playbackProgress: CGFloat
    ) -> some View {
        let start = fraction(for: range.lowerBound)
        let end = fraction(for: range.upperBound)
        let height = Self.highlightedTrackHeight
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.42))
                .frame(width: width * (end - start), height: height)
            ForEach(bufferedRanges.indices, id: \.self) { index in
                let buffered = bufferedRanges[index]
                let lower = max(fraction(for: buffered.lowerBound), start)
                let upper = min(fraction(for: buffered.upperBound), end)
                if upper > lower {
                    Rectangle()
                        .fill(.white.opacity(0.72))
                        .frame(width: width * (upper - lower), height: height)
                        .offset(x: width * (lower - start))
                }
            }
            if playbackProgress > start {
                Rectangle()
                    .fill(scrubberColor)
                    .saturation(1.3)
                    .frame(width: width * (min(playbackProgress, end) - start), height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .offset(x: width * start)
    }

    /// SponsorBlock ranges match the track's thickness, including inside the enlarged chapter.
    private func segmentHeight(
        _ segment: SponsorBlockSegment,
        in highlight: ClosedRange<TimeInterval>?
    ) -> CGFloat {
        guard let highlight,
              segment.startTime < highlight.upperBound,
              segment.endTime > highlight.lowerBound else { return Self.trackHeight }
        return Self.highlightedTrackHeight
    }

    private func fraction(for time: TimeInterval) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1))
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

/// About 36 points of touch for the 24-point track frame: 4 points up into the gap below the
/// time labels, 8 down into the timeline's bottom padding, and 12 past each end.
private struct TimelineTouchShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 12, y: rect.minY - 4, width: rect.width + 24, height: rect.height + 12))
    }
}
