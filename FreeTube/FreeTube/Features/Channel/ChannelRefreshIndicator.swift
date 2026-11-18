import SwiftUI

/// Pull-to-refresh feedback centred in the gap that opens above a channel page's list. The
/// immersive header covers the system refresh control, so this is drawn in the page content.
/// Reads the pull distance itself so a drag redraws only this view.
@available(iOS 17.0, *)
struct ChannelRefreshIndicator: View {
    let pagerState: ChannelPagerState
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Roughly where UIKit's refresh control commits to a refresh.
    private static let triggerDistance: CGFloat = 90
    private static let size: CGFloat = 28

    var body: some View {
        let pull = pagerState.pullDistance
        let progress = min(1, pull / Self.triggerDistance)
        let visible = isRefreshing || pull > 4
        // The visible gap is the list's top spacing plus however far the page is pulled down.
        let gap = ChannelProfileMetrics.contentTopInset + pull
        ZStack {
            if isRefreshing {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
                    .opacity(0.4 + 0.6 * progress)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .offset(y: -(gap + Self.size) / 2)
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRefreshing)
        .allowsHitTesting(false)
        .accessibilityLabel("Refreshing channel")
        .accessibilityHidden(!visible)
    }
}
