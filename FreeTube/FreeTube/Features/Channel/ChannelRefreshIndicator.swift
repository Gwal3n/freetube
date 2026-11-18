import SwiftUI

/// Pull-to-refresh feedback drawn above the channel's immersive header, which covers the
/// system refresh control. Reads the pull distance itself so a drag redraws only this view.
@available(iOS 17.0, *)
struct ChannelRefreshIndicator: View {
    let pagerState: ChannelPagerState
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Roughly where UIKit's refresh control commits to a refresh.
    private static let triggerDistance: CGFloat = 90

    var body: some View {
        let pull = pagerState.pullDistance
        let progress = min(1, pull / Self.triggerDistance)
        let visible = isRefreshing || pull > 4
        ZStack {
            if isRefreshing {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
                    .opacity(0.4 + 0.6 * progress)
            }
        }
        .frame(width: 32, height: 32)
        .background(.ultraThinMaterial, in: Circle())
        .padding(.top, 8)
        .offset(y: isRefreshing ? 0 : min(pull, Self.triggerDistance) * 0.35)
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRefreshing)
        .allowsHitTesting(false)
        .accessibilityLabel("Refreshing channel")
        .accessibilityHidden(!visible)
    }
}
