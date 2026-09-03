import SwiftUI

@available(iOS 17.0, *)
struct CustomPlayerControls: View {
    let isVisible: Bool
    let isSeekPreviewActive: Bool
    let isPlaying: Bool
    let hasEnded: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let sponsorSegments: [SponsorBlockSegment]
    let chapters: [VideoChapter]
    let hasPrevious: Bool
    let hasNext: Bool
    let additionalTopControls: AnyView
    let bottomTimelinePadding: CGFloat
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.28 : 0)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.down")
                            .playerTopControl()
                    }
                    Spacer()
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
                    Button(action: onTogglePlayPause) {
                        Image(systemName: hasEnded ? "arrow.counterclockwise" : (isPlaying ? "pause.fill" : "play.fill"))
                            .font(.system(size: 34, weight: .semibold))
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
                }
                .buttonStyle(.plain)
                .opacity(isVisible ? 1 : 0)

                Spacer()

                SponsorBlockTimeline(
                    elapsed: elapsed,
                    duration: duration,
                    segments: sponsorSegments,
                    chapters: chapters,
                    onSeek: onSeek
                )
                .padding(.horizontal, 12)
                .padding(.bottom, bottomTimelinePadding)
                .opacity(isVisible || isSeekPreviewActive ? 1 : 0)
            }
        }
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible && !isSeekPreviewActive)
        .animation(.easeInOut(duration: 0.24), value: isVisible)
        .animation(.easeInOut(duration: 0.12), value: isSeekPreviewActive)
    }

}

extension Image {
    func playerTopControl() -> some View {
        font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
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
