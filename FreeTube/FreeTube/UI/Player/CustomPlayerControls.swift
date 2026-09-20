import SwiftUI

@available(iOS 17.0, *)
struct CustomPlayerControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool
    let isSeekPreviewActive: Bool
    let isPlaying: Bool
    let hasEnded: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isLive: Bool
    let sponsorSegments: [SponsorBlockSegment]
    let chapters: [VideoChapter]
    let hasPrevious: Bool
    let hasNext: Bool
    let videoTitle: String
    let channelName: String
    let usesLandscapeLayout: Bool
    let showsCollapseButton: Bool
    let additionalTopControls: AnyView
    let bottomTimelinePadding: CGFloat
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSeekPreviewChanged: (TimeInterval?) -> Void
    let onShowChapters: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    if showsCollapseButton {
                        Button(action: onCollapse) {
                            Image(systemName: "chevron.down")
                                .playerTopControl()
                        }
                        .accessibilityLabel("Minimize player")
                        Spacer()
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(videoTitle)
                                .font(usesLandscapeLayout
                                    ? .headline.weight(.semibold)
                                    : .subheadline.weight(.semibold))
                                .lineLimit(1)
                            if !channelName.isEmpty {
                                Text(channelName)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                    additionalTopControls
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .opacity(isVisible ? 1 : 0)

                Spacer()

                HStack(spacing: 42) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill").playerCenterControl()
                    }
                    .disabled(!hasPrevious)
                    .accessibilityLabel("Previous video")
                    Button(action: onTogglePlayPause) {
                        Group {
                            if hasEnded {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 34, weight: .semibold))
                            } else {
                                PlayPauseMorphIcon(isPlaying: isPlaying)
                                    .frame(width: 40, height: 40)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .contentShape(Circle())
                        .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                    }
                    .accessibilityLabel(hasEnded ? "Replay" : (isPlaying ? "Pause" : "Play"))
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill").playerCenterControl()
                    }
                    .disabled(!hasNext)
                    .accessibilityLabel("Next video")
                }
                .buttonStyle(.plain)
                .opacity(isVisible ? 1 : 0)

                Spacer()

                SponsorBlockTimeline(
                    elapsed: elapsed,
                    duration: duration,
                    isLive: isLive,
                    segments: sponsorSegments,
                    chapters: chapters,
                    onSeek: onSeek,
                    onPreviewChanged: onSeekPreviewChanged,
                    onShowChapters: onShowChapters
                )
                .padding(.horizontal, 12)
                .padding(.bottom, bottomTimelinePadding)
                .opacity(isVisible || isSeekPreviewActive ? 1 : 0)
            }
        }
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible && !isSeekPreviewActive)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isSeekPreviewActive)
    }

}

/// A continuous play-to-pause morph. Both states use the same pair of four-point polygons, so
/// SwiftUI interpolates their geometry instead of shrinking one SF Symbol before inserting the
/// other. The two polygons meet as a triangle in the play state and separate into pause bars.
struct PlayPauseMorphIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPlaying: Bool

    var body: some View {
        PlayPauseMorphShape(progress: isPlaying ? 1 : 0)
            .fill(.primary)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.18, extraBounce: 0),
                value: isPlaying
            )
    }
}

private struct PlayPauseMorphShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let playUpper = [
            CGPoint(x: 0.22, y: 0.14),
            CGPoint(x: 0.22, y: 0.50),
            CGPoint(x: 0.84, y: 0.50),
            CGPoint(x: 0.84, y: 0.50)
        ]
        let playLower = [
            CGPoint(x: 0.22, y: 0.50),
            CGPoint(x: 0.22, y: 0.86),
            CGPoint(x: 0.84, y: 0.50),
            CGPoint(x: 0.84, y: 0.50)
        ]
        let pauseLeft = rectanglePoints(minX: 0.22, maxX: 0.42)
        let pauseRight = rectanglePoints(minX: 0.60, maxX: 0.80)

        var path = Path()
        addPolygon(interpolate(playUpper, pauseLeft), in: rect, to: &path)
        addPolygon(interpolate(playLower, pauseRight), in: rect, to: &path)
        return path
    }

    private func rectanglePoints(minX: CGFloat, maxX: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: minX, y: 0.14),
            CGPoint(x: minX, y: 0.86),
            CGPoint(x: maxX, y: 0.86),
            CGPoint(x: maxX, y: 0.14)
        ]
    }

    private func interpolate(_ from: [CGPoint], _ to: [CGPoint]) -> [CGPoint] {
        zip(from, to).map { start, end in
            CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
        }
    }

    private func addPolygon(_ points: [CGPoint], in rect: CGRect, to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: scaled(first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: scaled(point, in: rect))
        }
        path.closeSubpath()
    }

    private func scaled(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

extension Image {
    func playerTopControl() -> some View {
        font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
    }

    func playerCenterControl() -> some View {
        font(.system(size: 27, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}
