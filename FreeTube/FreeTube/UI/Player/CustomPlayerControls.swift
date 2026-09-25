import SwiftUI

@available(iOS 17.0, *)
struct CustomPlayerControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool
    let isPreparing: Bool
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
    let topControlsSafeAreaPadding: CGFloat
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
                .padding(.top, 8 + topControlsSafeAreaPadding)
                .opacity(isVisible ? 1 : 0)

                Spacer()

                HStack(spacing: 42) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill").playerCenterControl()
                    }
                    .disabled(!hasPrevious)
                    .accessibilityLabel("Previous video")
                    Group {
                        if isPreparing {
                            PlaybackActivityIndicator(size: 34, lineWidth: 3.5)
                                .frame(width: 68, height: 68)
                                .allowsHitTesting(false)
                                .accessibilityLabel("Preparing video")
                        } else {
                            Button(action: onTogglePlayPause) {
                                Group {
                                    if hasEnded {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 34, weight: .semibold))
                                    } else {
                                        PlaybackMorphShape(progress: isPlaying ? 1 : 0)
                                            .fill(.white)
                                            .frame(width: 34, height: 34)
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(width: 68, height: 68)
                                .contentShape(Circle())
                                .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.14),
                                    value: isPlaying
                                )
                            }
                            .accessibilityLabel(hasEnded ? "Replay" : (isPlaying ? "Pause" : "Play"))
                        }
                    }
                    .frame(width: 68, height: 68)
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
        .allowsHitTesting(isVisible && !isPreparing)
        .accessibilityHidden(!isVisible && !isSeekPreviewActive)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isSeekPreviewActive)
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
            .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
    }
}
