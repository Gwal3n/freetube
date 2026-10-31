import SwiftUI

/// Channel tabs and the underline that tracks the pager while it moves.
@available(iOS 17.0, *)
struct ChannelProfileTabBar: View {
    let tabs: [ChannelProfileTab]
    let selectedTab: ChannelProfileTab
    let pagePosition: CGFloat
    let reduceMotion: Bool
    let onSelect: (ChannelProfileTab) -> Void

    @State private var tabFrames: [String: CGRect] = [:]
    private static let tabRowSpace = "channelTabRow"

    /// Tabs sized to their own labels inside a horizontal scroller.
    ///
    /// The previous version divided the container width into equal segments through a
    /// `GeometryReader`. That couples the tab bar to whatever width its ancestors report, so it
    /// stretched into sparse columns on a wide container and pushed the later tabs off-screen on a
    /// narrow one — and it inherited any incorrect width from elsewhere in the screen. Intrinsic
    /// widths inside a scroller can do neither: the labels keep their natural spacing at any size,
    /// and when they genuinely exceed the width the row scrolls instead of truncating.
    ///
    /// The underline is a single view positioned from the measured label frames and interpolated
    /// by the pager's live scroll offset, so it is wherever the content is at every instant of a
    /// swipe — including a swipe that gets abandoned and springs back.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 26) {
                    ForEach(tabs) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            onSelect(tab)
                        } label: {
                            VStack(spacing: 7) {
                                Text(tab.title)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.5))
                                    .fixedSize()
                                // Reserves the underline's row so the labels don't shift when it
                                // moves; the underline itself is drawn once, in the overlay below.
                                Color.clear.frame(height: 2.5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(tab.id)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ChannelTabFrameKey.self,
                                    value: [tab.id: geometry.frame(in: .named(Self.tabRowSpace))]
                                )
                            }
                        }
                    }
                }
                .coordinateSpace(name: Self.tabRowSpace)
                .overlay(alignment: .bottomLeading) {
                    if let indicator = indicatorFrame(tabs: tabs) {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: indicator.width, height: 2.5)
                            .offset(x: indicator.minX)
                            // Already an exact function of where the pager is, including while a
                            // tap-driven scroll animates. An implicit animation on top of that
                            // would be a second, slower copy of the same movement.
                            .transaction { $0.animation = nil }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .onPreferenceChange(ChannelTabFrameKey.self) { frames in
                tabFrames = frames
            }
            // Keep the active tab reachable when the row is wider than the screen.
            .onChange(of: selectedTab) { _, tab in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(tab.id, anchor: .center)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    /// Where the underline sits right now, read straight off the pager's live scroll offset.
    ///
    /// Because `pagePosition` is continuous, the underline is wherever the content is: halfway
    /// through a swipe it sits halfway between the two labels, at the width between theirs, and it
    /// reverses with the finger if the swipe is abandoned. Nothing here is animated — it doesn't
    /// need to be, since the value it reads is already following the gesture.
    private func indicatorFrame(tabs: [ChannelProfileTab]) -> CGRect? {
        guard !tabs.isEmpty else { return nil }

        let position = min(max(pagePosition, 0), CGFloat(tabs.count - 1))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, tabs.count - 1)
        let blend = position - CGFloat(lowerIndex)

        guard let lower = tabFrames[tabs[lowerIndex].id] else { return nil }
        guard let upper = tabFrames[tabs[upperIndex].id] else { return lower }

        return CGRect(
            x: lower.minX + (upper.minX - lower.minX) * blend,
            y: lower.minY,
            width: lower.width + (upper.width - lower.width) * blend,
            height: lower.height
        )
    }
}
