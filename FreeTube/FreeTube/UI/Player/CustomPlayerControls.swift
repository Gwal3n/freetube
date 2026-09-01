import SwiftUI

@available(iOS 17.0, *)
struct CustomPlayerControls: View {
    let isVisible: Bool
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let playbackRate: Double
    let sponsorSegments: [SponsorBlockSegment]
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSeekRelative: (TimeInterval) -> Void
    let onSetRate: (Double) -> Void
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.28 : 0)
                .allowsHitTesting(false)

            if isVisible {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onCollapse) {
                            Image(systemName: "chevron.down")
                                .playerControlCircle()
                        }
                        Spacer()
                        Menu {
                            ForEach([0.5, 1, 1.25, 1.5, 2], id: \.self) { rate in
                                Button {
                                    onSetRate(rate)
                                } label: {
                                    if abs(playbackRate - rate) < 0.01 {
                                        Label(rateLabel(rate), systemImage: "checkmark")
                                    } else {
                                        Text(rateLabel(rate))
                                    }
                                }
                            }
                        } label: {
                            Text(rateLabel(playbackRate))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 42, minHeight: 36)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Spacer()

                    HStack(spacing: 42) {
                        Button { onSeekRelative(-10) } label: {
                            Image(systemName: "gobackward.10").playerCenterControl()
                        }
                        Button(action: onTogglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 58)
                                .background(.black.opacity(0.62), in: Circle())
                        }
                        Button { onSeekRelative(10) } label: {
                            Image(systemName: "goforward.10").playerCenterControl()
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    SponsorBlockTimeline(
                        elapsed: elapsed,
                        duration: duration,
                        segments: sponsorSegments,
                        onSeek: onSeek
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

private extension Image {
    func playerControlCircle() -> some View {
        font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(.black.opacity(0.55), in: Circle())
    }

    func playerCenterControl() -> some View {
        font(.system(size: 27, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}
