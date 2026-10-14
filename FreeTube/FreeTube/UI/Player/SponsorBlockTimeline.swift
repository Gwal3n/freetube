import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockTimeline: View {
    let elapsed: TimeInterval
    let previewElapsed: TimeInterval?
    let duration: TimeInterval
    let isPlaying: Bool
    let canStepBackward: Bool
    let canStepForward: Bool
    let bufferedRanges: [ClosedRange<TimeInterval>]
    let isLive: Bool
    let segments: [SponsorBlockSegment]
    let chapters: [VideoChapter]
    let onSeek: (TimeInterval) -> Void
    let onPreviewChanged: (TimeInterval?) -> Void
    let onShowChapters: () -> Void
    let onStepFrame: (Int) -> Void

    @State private var dragTime: TimeInterval?
    @State private var isPreviewingDrag = false
    @State private var scrubChapterID: VideoChapter.ID?
    @State private var chapterHapticTrigger = 0
    @State private var isFrameStepMode = false

    private var displayedTime: TimeInterval { dragTime ?? previewElapsed ?? elapsed }
    private var currentChapter: VideoChapter? {
        chapters.last { $0.startTime <= displayedTime }
    }
    private var fullVideoLabel: SponsorBlockCategory? {
        SponsorBlockSegment.primaryFullVideoLabel(in: segments)
    }

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
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                // The track follows the finger, but the elapsed clock remains the real
                // playback position until the seek is committed.
                Text(verbatim: format(elapsed))
                if isFrameStepMode {
                    HStack(spacing: 2) {
                        Button {
                            onStepFrame(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 34, height: 28)
                        }
                        .disabled(!canStepBackward)
                        .accessibilityLabel("Fine step backward")

                        Button {
                            onStepFrame(1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 34, height: 28)
                        }
                        .disabled(!canStepForward)
                        .accessibilityLabel("Fine step forward")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                } else if let currentChapter {
                    Button(action: onShowChapters) {
                        HStack(spacing: 3) {
                            Text(verbatim: currentChapter.title)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: 190, alignment: .leading)
                    }
                    // Expand only the interactive shape; keep the compact chapter typography and
                    // timeline layout unchanged.
                    .contentShape(.interaction, Rectangle().inset(by: -10))
                    .accessibilityLabel("Current chapter, \(currentChapter.title)")
                }
                Spacer()
                if !isPlaying && (canStepBackward || canStepForward) {
                    Button {
                        isFrameStepMode.toggle()
                    } label: {
                        Image(systemName: isFrameStepMode ? "film.fill" : "film")
                            .frame(width: 34, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFrameStepMode ? "Close fine seeking" : "Fine seeking")
                }
                Text(verbatim: format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let progress = fraction(for: displayedTime)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                    ForEach(bufferedRanges.indices, id: \.self) { index in
                        let range = bufferedRanges[index]
                        let start = fraction(for: range.lowerBound)
                        let end = fraction(for: range.upperBound)
                        Capsule()
                            .fill(.white.opacity(0.55))
                            .frame(width: width * max(0, end - start), height: 4)
                            .offset(x: width * start)
                    }
                    Capsule().fill(.red).frame(width: width * progress, height: 4)

                    // Full-video labels are annotations, never a seek target. Keep their slim
                    // stripe below the progress track so the red playback position stays clear.
                    if let fullVideoLabel {
                        Capsule()
                            .fill(color(for: fullVideoLabel))
                            .frame(width: width, height: 2)
                            .offset(y: 5)
                    }

                    ForEach(segments.filter { $0.category != .chapter && !$0.isFullVideoLabel }, id: \.id) { segment in
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
                            .fill(.black)
                            .frame(width: 2, height: 4)
                            .offset(x: min(max(width * fraction(for: chapter.startTime) - 1, 0), width - 2))
                            .blendMode(.destinationOut)
                    }

                    Circle()
                        .fill(.red)
                        .frame(width: 14, height: 14)
                        .offset(x: min(max(width * progress - 7, 0), width - 14))
                }
                .compositingGroup()
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
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
        .onChange(of: isPlaying) { _, playing in
            if playing { isFrameStepMode = false }
        }
        .onChange(of: canStepBackward || canStepForward) { _, available in
            if !available { isFrameStepMode = false }
        }
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

    private func fraction(for time: TimeInterval) -> CGFloat {
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1))
    }

    private func color(for category: SponsorBlockCategory) -> Color {
        switch category {
        case .sponsor: return .green
        case .selfPromotion: return .yellow
        case .exclusiveAccess: return Color(red: 0, green: 138.0 / 255, blue: 92.0 / 255)
        case .interaction: return .pink
        case .intro: return .cyan
        case .outro: return .blue
        case .preview: return Color(red: 0, green: 143.0 / 255, blue: 214.0 / 255)
        case .hook: return Color(red: 1, green: 128.0 / 255, blue: 0)
        case .musicOfftopic: return Color(red: 1, green: 153.0 / 255, blue: 0)
        case .filler: return Color(red: 115.0 / 255, green: 0, blue: 1)
        case .highlight: return .purple
        case .chapter: return .white
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
