import SwiftUI

@available(iOS 17.0, *)
struct CustomPlayerControls: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let isVisible: Bool
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let playbackRate: Double
    let sponsorSegments: [SponsorBlockSegment]
    let hasPrevious: Bool
    let hasNext: Bool
    let additionalTopControls: AnyView
    let onTogglePlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSetRate: (Double) -> Void
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
                            .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 42) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill").playerCenterControl()
                    }
                    .disabled(!hasPrevious)
                    Button(action: onTogglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 68, height: 68)
                            .contentShape(Circle())
                            .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                    }
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill").playerCenterControl()
                    }
                    .disabled(!hasNext)
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
                .padding(.bottom, verticalSizeClass == .compact ? 22 : 8)
            }
            .opacity(isVisible ? 1 : 0)
        }
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeInOut(duration: 0.24), value: isVisible)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1 ? "1×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

private extension Image {
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
