import SwiftUI
import Kingfisher
import UIKit

@available(iOS 17.0, *)
struct ChannelScreen: View {
    @State private var model: ChannelViewModel
    @State private var selectedTab: ChannelProfileTab = .videos
    @State private var videoSort: ChannelVideoSort = .newest
    /// Laid-out frame of each tab label, keyed by `ChannelProfileTab.id`, in the tab row's own
    /// coordinate space. The underline is positioned by interpolating between two of these, so it
    /// tracks the pager continuously rather than jumping when a swipe settles.
    @State private var tabFrames: [String: CGRect] = [:]
    /// Live horizontal offset of the pager, in points. Divided by the page width this gives a
    /// fractional page position — 1.4 means "40% of the way from tab 1 to tab 2".
    @State private var pagerOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    @State private var pageViewportHeight: CGFloat = 0
    /// Pending "scroll yourself down to here" requests, keyed by tab id. See `alignPages`.
    @State private var pageScrollTargets: [String: PageScrollTarget] = [:]
    /// Vertical scroll offset of each page, keyed by tab id. Only the active page's value is used,
    /// but they are kept per tab so switching tabs restores that tab's own header state.
    @State private var pageOffsets: [String: CGFloat] = [:]
    /// Seeded with estimates rather than zero. These are replaced by the measured values on the
    /// first layout pass, but starting at zero would put every page's first row under the header
    /// for one frame and then shove it down, which reads as a flinch each time a channel opens.
    @State private var headerContentHeight: CGFloat = Metrics.estimatedHeaderHeight
    @State private var tabBarHeight: CGFloat = Metrics.estimatedTabBarHeight

    private static let tabRowSpace = "channelTabRow"
    private static let pagerSpace = "channelPager"
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let prefetchLookahead = 5

    init(channelID: String) {
        _model = State(wrappedValue: ChannelViewModel(channelID: channelID))
    }

    /// Collapsing header over a horizontal pager — the shape YouTube and X use for profiles.
    ///
    /// Each tab owns a real vertical `ScrollView`, and those pages sit in a horizontal
    /// `ScrollView` with paging scroll-target behaviour. Every gesture on this screen is therefore
    /// a system scroll gesture, which is the substantive change: the previous custom `DragGesture`
    /// had to run alongside the rows' own controls, so a sideways swipe could still land as a tap
    /// on a `NavigationLink` and a slow vertical drag could be read as a long press. A `UIScrollView`
    /// cancels touches in its subviews once it starts scrolling, so both resolve themselves, and
    /// the interactive pop gesture at the leading edge keeps working without being fenced off.
    ///
    /// The header is not inside any scroll view. It is drawn above the pager and translated up by
    /// the active page's scroll offset, which is why each page reserves an equal amount of empty
    /// space at the top: the content and the header move together at exactly 1:1, instead of the
    /// double movement you get from putting a collapsing header inside the thing that scrolls it.
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let details = model.details {
                pager(details)
                header(details)
            } else {
                channelHeaderPlaceholder
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A principal item rather than `navigationTitle`, because the title has to fade rather
            // than appear: it stays hidden while the channel's own name is on screen in the header,
            // and takes over only once that name has scrolled under the bar.
            ToolbarItem(placement: .principal) {
                Text(model.details?.channel.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .offset(y: showsNavigationTitle ? 0 : 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsNavigationTitle)
            }
            channelActionsToolbar
        }
        // Transparent over the banner, which is what makes the top of the screen feel immersive,
        // then solid black on the same trigger as the title. Black rather than a material because
        // by the time the title appears the header behind the bar is also black, and a blur would
        // draw a seam across a surface that should read as one continuous piece with the tab row.
        .toolbarBackground(showsNavigationTitle ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load() }
        .task(id: videoSort) {
            guard model.details != nil, videoSort != .newest else { return }
            await model.loadVideos(sort: videoSort)
        }
        .errorToast(Bindable(model).errorState)
    }

    // MARK: - Derived scroll state

    private var currentTabs: [ChannelProfileTab] {
        model.details.map(availableTabs(for:)) ?? []
    }

    /// Vertical scroll offset driving the header, blended across the two pages a swipe sits
    /// between.
    ///
    /// This is the backstop, not the main mechanism. `alignPages` keeps the pages in agreement so
    /// there is normally nothing to blend; the interpolation only matters in the one case it
    /// cannot fix — arriving at a tab that is scrolled *deeper* than the current header position,
    /// where the header has to collapse to meet it. Moving that across the swipe instead of in a
    /// single frame is the difference between a slide and a jump.
    private var activePageOffset: CGFloat {
        let tabs = currentTabs
        guard !tabs.isEmpty else { return 0 }
        let position = min(max(pagePosition, 0), CGFloat(tabs.count - 1))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, tabs.count - 1)
        let blend = position - CGFloat(lowerIndex)
        let lower = max(0, pageOffsets[tabs[lowerIndex].id] ?? 0)
        let upper = max(0, pageOffsets[tabs[upperIndex].id] ?? 0)
        return lower + (upper - lower) * blend
    }

    /// How far the header is currently translated up. Stops at the header's own height so the tab
    /// bar comes to rest against the navigation bar and stays there.
    private var headerCollapse: CGFloat {
        min(activePageOffset, headerContentHeight)
    }

    /// Total space each page reserves at the top so its first row starts below the header.
    private var headerTotalHeight: CGFloat {
        headerContentHeight + tabBarHeight
    }

    /// The title takes over only once the header is fully collapsed — that is, once the last of
    /// the channel's own name, stats and subscribe button has gone under the bar. Revealing it at
    /// a fixed depth part-way through put it on screen while the subscribe button was still
    /// visible below it, which read as two competing titles.
    private var showsNavigationTitle: Bool {
        guard headerContentHeight > 0 else { return false }
        return activePageOffset > headerContentHeight - Metrics.navigationTitleLead
    }

    /// Fractional page position: 1.4 means 40% of the way from the second tab to the third.
    private var pagePosition: CGFloat {
        guard pageWidth > 0 else { return 0 }
        return max(0, pagerOffset / pageWidth)
    }

    /// True as soon as the pager leaves a whole page, i.e. the moment a sideways drag begins.
    /// The threshold is about four points, so the neighbouring page is barely a sliver on screen
    /// when this flips — early enough to align it before anyone can see it move.
    private var isPagingActive: Bool {
        guard pageWidth > 0 else { return false }
        return abs(pagePosition - pagePosition.rounded()) > 0.01
    }

    /// Moves every page that is *not* driving the header down to where the header already is.
    ///
    /// This is the piece that removes the jump rather than smoothing it. The header can only sit
    /// at one height, but each tab owns its own scroll position, and a page's content is laid out
    /// assuming the header is wherever that page is scrolled to. So the two have to be reconciled,
    /// and the choice is which one moves: previously the header moved to meet the incoming page,
    /// which is the several-hundred-point lurch. Here the incoming page moves instead, silently,
    /// before it is on screen — so the header simply stays put across the swipe.
    ///
    /// Deliberately forward-only. Scrolling a page *backwards* to meet a more expanded header
    /// would throw away however far the user had read into that tab, which is a worse trade than
    /// the header moving. That case is left to the interpolation in `activePageOffset`.
    private func alignPages(excluding driver: ChannelProfileTab) {
        let collapse = headerCollapse
        guard collapse > 1 else { return }
        for tab in currentTabs where tab.id != driver.id {
            guard (pageOffsets[tab.id] ?? 0) < collapse - 1 else { continue }
            let token = (pageScrollTargets[tab.id]?.token ?? 0) + 1
            pageScrollTargets[tab.id] = PageScrollTarget(y: collapse, token: token)
        }
    }

    /// Two-way bridge between `selectedTab` and the pager's scroll position. Tapping a tab writes
    /// `selectedTab`, which moves the pager; swiping moves the pager, which writes `selectedTab`.
    private var pagerSelection: Binding<String?> {
        Binding(
            get: { selectedTab.id },
            set: { newValue in
                guard let newValue,
                      let tab = ChannelProfileTab(rawValue: newValue),
                      tab != selectedTab else { return }
                selectedTab = tab
            }
        )
    }

    // MARK: - Pager

    private func pager(_ details: ChannelDetails) -> some View {
        let tabs = availableTabs(for: details)

        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(tabs) { tab in
                    page(details, tab: tab)
                        // Exactly one page wide, so paging lands cleanly and the fractional
                        // position derived from the offset is meaningful.
                        .containerRelativeFrame(.horizontal)
                        .id(tab.id)
                }
            }
            .scrollTargetLayout()
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChannelPagerOffsetKey.self,
                        value: -geometry.frame(in: .named(Self.pagerSpace)).minX
                    )
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: pagerSelection)
        .scrollIndicators(.hidden)
        .coordinateSpace(name: Self.pagerSpace)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ChannelPageWidthKey.self, value: geometry.size.width)
            }
        }
        // Consumed only where the exact API below is unavailable, so the two never fight.
        .onPreferenceChange(ChannelPagerOffsetKey.self) { value in
            if #unavailable(iOS 18.0) { pagerOffset = value }
        }
        .onPreferenceChange(ChannelPageWidthKey.self) { value in
            if #unavailable(iOS 18.0) { pageWidth = value }
        }
        .modifier(PagerScrollGeometry(offset: $pagerOffset, width: $pageWidth, height: $pageViewportHeight))
        .onChange(of: isPagingActive) { _, active in
            if active { alignPages(excluding: selectedTab) }
        }
    }

    private func page(_ details: ChannelDetails, tab: ChannelProfileTab) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // Reserves the header's footprint, plus a little air so the first row isn't
                // crowded against the tab bar. The header is drawn over the top of this.
                Color.clear.frame(height: headerTotalHeight + Metrics.contentTopInset)
                // The minimum height is what lets a short tab — About, or a channel with three
                // videos — still scroll far enough to hold the header collapsed. Without it that
                // tab has no room to accept an alignment, so arriving at it would spring the
                // header back open. The cost is that a short tab can be scrolled past its content
                // into empty space, which is the same bargain every tabbed profile makes.
                channelContent(details, tab: tab)
                    .frame(maxWidth: .infinity, minHeight: pageViewportHeight, alignment: .topLeading)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChannelPageOffsetKey.self,
                        value: [tab.id: -geometry.frame(in: .named(Self.pageSpace(tab))).minY]
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: Self.pageSpace(tab))
        .onPreferenceChange(ChannelPageOffsetKey.self) { offsets in
            if #unavailable(iOS 18.0) { pageOffsets.merge(offsets) { _, new in new } }
        }
        .modifier(PageScrollGeometry(tab: tab.id, offsets: $pageOffsets))
        .modifier(PageScrollAlignment(request: pageScrollTargets[tab.id]))
    }

    private static func pageSpace(_ tab: ChannelProfileTab) -> String {
        "channelPage-\(tab.id)"
    }

    // MARK: - Header

    private func header(_ details: ChannelDetails) -> some View {
        VStack(spacing: 0) {
            channelHeader(details.channel)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChannelHeaderHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            channelTabBar(details)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ChannelTabBarHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
        }
        // Opaque, because the pages scroll underneath it rather than below it.
        .background(Color.black)
        .offset(y: -headerCollapse)
        .onPreferenceChange(ChannelHeaderHeightKey.self) { headerContentHeight = $0 }
        .onPreferenceChange(ChannelTabBarHeightKey.self) { tabBarHeight = $0 }
    }

    @ToolbarContentBuilder
    private var channelActionsToolbar: some ToolbarContent {
        if let channel = model.details?.channel,
           let url = channelURL(channel) {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: url) {
                        Label("Share channel", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.url = url
                    } label: {
                        Label("Copy channel link", systemImage: "link")
                    }
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Channel actions")
            }
        }
    }

    // MARK: - Header

    /// Named `Metrics` rather than `Layout` so it can't be confused with SwiftUI's `Layout`
    /// protocol, which a nested type of that name would shadow throughout this file.
    private enum Metrics {
        static let bannerHeight: CGFloat = 190
        static let avatarSize: CGFloat = 92
        /// How far the avatar hangs below the banner — half its height, so it sits centred on the
        /// banner's bottom edge.
        static var avatarOverhang: CGFloat { avatarSize / 2 }
        /// Scroll distance at which the header's channel name has cleared the navigation bar.
        /// Derived from the geometry above so it stays correct if the banner or avatar changes.
        /// How far before the header is fully collapsed the navigation title starts to appear.
        static let navigationTitleLead: CGFloat = 20
        /// Breathing room between the tab bar and the first row of content.
        static let contentTopInset: CGFloat = 12
        /// First-frame approximations only — both are corrected by measurement immediately.
        /// Banner, avatar overhang, the name/handle/stats block, the subscribe capsule, spacing.
        static var estimatedHeaderHeight: CGFloat { bannerHeight + avatarOverhang + 162 }
        static let estimatedTabBarHeight: CGFloat = 44
    }

    /// Mirrors the loaded header's geometry so the screen doesn't jump when content arrives.
    private var channelHeaderPlaceholder: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(Color(white: 0.14))
                .frame(height: Metrics.bannerHeight)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(Color(white: 0.2))
                        .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 4))
                        .offset(y: Metrics.avatarOverhang)
                }
                .padding(.bottom, Metrics.avatarOverhang)

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.2)).frame(width: 180, height: 20)
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.16)).frame(width: 120, height: 12)
            }
            Capsule().fill(Color(white: 0.16)).frame(width: 140, height: 38)
        }
        .padding(.bottom, 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading channel")
        .allowsHitTesting(false)
    }

    /// Centred profile block with the avatar straddling the bottom edge of the banner.
    ///
    /// Centred rather than the leading row this replaced, for two reasons. It reads as a profile
    /// rather than as a list row, which is the Apple-style shape this screen wants; and it has no
    /// `Spacer` throwing the subscribe button at the trailing edge, so the block stays composed at
    /// any width instead of stretching the avatar and the button apart as the container grows.
    private func channelHeader(_ channel: Channel) -> some View {
        VStack(spacing: 14) {
            banner(channel)
                // The avatar hangs half outside the banner. An overlay never contributes to its
                // host's size, so the overhang is reclaimed explicitly with the matching padding
                // below rather than by letting the avatar stretch the banner's frame.
                .overlay(alignment: .bottom) {
                    avatar(channel).offset(y: Metrics.avatarOverhang)
                }
                .padding(.bottom, Metrics.avatarOverhang)

            VStack(spacing: 5) {
                Text(channel.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let handle = channel.handle, !handle.isEmpty {
                    Text(handle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                if !channelStats(channel).isEmpty {
                    Text(channelStats(channel))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24)

            subscribeButton(channel)
        }
        .padding(.bottom, 22)
    }

    private func avatar(_ channel: Channel) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.16))
            Text(channel.name.prefix(1).uppercased())
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            KFImage(channel.thumbnailURL)
                .thumbnail(size: CGSize(width: Metrics.avatarSize, height: Metrics.avatarSize)) {
                    Color.clear
                }
                .resizable()
                .scaledToFill()
                // Both axes, always. A `scaledToFill` image constrained on one axis reports the
                // size it needs to *cover* the other, which is how an image ends up wider than its
                // container and, through the container, wider than the screen.
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
        }
        .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black, lineWidth: 4))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
    }

    /// Full-bleed banner whose size is defined by an empty spacer, not by the image.
    ///
    /// `Color.clear` is the only thing here that participates in layout: it accepts the proposed
    /// width and the fixed height, and that is the size the banner reports to the header. The
    /// artwork lives in an `overlay`, which by contract cannot influence its host's size no matter
    /// what it asks for — so a wide banner scaled to fill overflows and is clipped, instead of
    /// widening this view. The previous version let a `scaledToFill` image size the container with
    /// only a height to go on; a 6:1 banner asked to be 178pt tall reports itself roughly 1075pt
    /// wide, and every ancestor inherited that.
    private func banner(_ channel: Channel) -> some View {
        Color.clear
            .frame(height: Metrics.bannerHeight)
            .overlay {
                if let bannerURL = channel.bannerURL {
                    KFImage(bannerURL)
                        .thumbnail(size: CGSize(width: 900, height: 300)) {
                            bannerPlaceholder
                        }
                        .resizable()
                        .scaledToFill()
                } else {
                    bannerPlaceholder
                }
            }
            .overlay {
                // Top scrim keeps the navigation title legible over a bright banner; the bottom one
                // dissolves the artwork into the black page background so the header reads as one
                // surface rather than a pasted-on image.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.85), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: [Color(white: 0.22), Color(white: 0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subscribed state is the quiet one. An unsubscribed channel gets a solid white capsule
    /// because subscribing is the screen's primary action; once subscribed the control becomes a
    /// low-contrast confirmation so it stops competing with the content below it.
    @ViewBuilder
    private func subscribeButton(_ channel: Channel) -> some View {
        Button {
            Task { await model.toggleSubscribe() }
        } label: {
            Group {
                if channel.isSubscribed {
                    Label("Subscribed", systemImage: "checkmark")
                } else {
                    Text("Subscribe")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(channel.isSubscribed ? Color.white : Color.black)
            // `fixedSize` so the capsule hugs its label. Without it the button inherits the
            // header's width and spans the screen.
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 26)
            .frame(height: 38)
            .background(
                channel.isSubscribed ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(Color.white),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(ResponsiveButtonStyle())
        .animation(reduceMotion ? nil : InterfaceMotion.quick, value: channel.isSubscribed)
    }

    // MARK: - Tabs

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
    private func channelTabBar(_ details: ChannelDetails) -> some View {
        let tabs = availableTabs(for: details)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 26) {
                    ForEach(tabs) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            selectTab(tab)
                        } label: {
                            VStack(spacing: 7) {
                                Text(tab.title)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
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
                            .fill(Color.white)
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
                .fill(.white.opacity(0.08))
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

    private func availableTabs(for details: ChannelDetails) -> [ChannelProfileTab] {
        var tabs: [ChannelProfileTab] = [.videos, .shorts]
        if !details.directs.items.isEmpty { tabs.append(.live) }
        tabs.append(contentsOf: [.playlists, .about])
        return tabs
    }

    private func selectTab(_ tab: ChannelProfileTab) {
        // Before the pager moves, not after — the destination has to already be at the header's
        // height by the time it slides into view.
        alignPages(excluding: selectedTab)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
            selectedTab = tab
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private func channelContent(_ details: ChannelDetails, tab: ChannelProfileTab) -> some View {
        switch tab {
        case .videos:
            videoSection(model.videos(for: videoSort))
        case .shorts:
            videoRows(details.shorts.items, emptyTitle: "No Shorts", kind: .shorts)
        case .live:
            videoRows(details.directs.items, emptyTitle: "No Live Videos", kind: .directs)
        case .playlists:
            playlistRows(details.playlists.items)
        case .about:
            aboutSection(details.channel)
        }
    }

    private func videoSection(_ videos: [Video]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    Picker("Sort videos", selection: $videoSort) {
                        ForEach(ChannelVideoSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                } label: {
                    Label(videoSort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if videos.isEmpty,
               (!model.hasLoadedVideos(for: videoSort) || model.isLoadingVideos(for: videoSort)) {
                // `MediaListPlaceholder` is `List`-backed and a `List` has no intrinsic height, so
                // it needs a bounded container. The other five call sites are screen roots or
                // overlays that supply one; this is the only one inside a `ScrollView`, where the
                // unbounded proposal leaves it laying out at an arbitrary height. Six rows, each a
                // thumbnail tall plus its row insets.
                MediaListPlaceholder()
                    .frame(height: 6 * (81 + MediaStyle.listRowInsets.top + MediaStyle.listRowInsets.bottom))
                    .padding(.horizontal, 16)
            } else {
                videoRows(videos, emptyTitle: "No Videos", kind: .allVideos)
            }
        }
    }

    @ViewBuilder
    private func videoRows(
        _ videos: [Video],
        emptyTitle: String,
        kind: ChannelViewModel.Tab
    ) -> some View {
        if videos.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "play.rectangle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    // No tap suppression needed any more: the enclosing scroll views cancel
                    // touches in their subviews once a scroll begins, so a swipe can no longer
                    // arrive here as a tap.
                    VideoRow(video: video, accessory: .actions(offersPlayNext: true)) {
                        player.load(video)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .onAppear { prefetchIfNeeded(index: index, total: videos.count, kind: kind) }
                }
                if canLoadMore(kind: kind) { loadingFooter(kind: kind) }
            }
        }
    }

    @ViewBuilder
    private func playlistRows(_ playlists: [Playlist]) -> some View {
        if playlists.isEmpty {
            ContentUnavailableView("No Playlists", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistScreen(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .onAppear { prefetchIfNeeded(index: index, total: playlists.count, kind: .playlists) }
                }
                if model.canLoadMore(for: .playlists) { loadingFooter(kind: .playlists) }
            }
        }
    }

    private func aboutSection(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").font(.title3.weight(.semibold))
                Text(aboutDescription(for: channel))
                    .font(.body)
                    .textSelection(.enabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let handle = channel.handle, !handle.isEmpty {
                    aboutRow(title: "Handle", value: handle, systemImage: "at")
                }
                if let subscribers = channel.subscriberCount {
                    aboutRow(title: "Subscribers", value: formattedCount(subscribers), systemImage: "person.2")
                }
                if let videos = channel.videoCount {
                    aboutRow(title: "Videos", value: formattedCount(videos), systemImage: "play.rectangle")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aboutRow(title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func aboutDescription(for channel: Channel) -> String {
        let description = channel.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? "This channel has not provided a description." : description
    }

    // MARK: - Pagination

    private func prefetchIfNeeded(index: Int, total: Int, kind: ChannelViewModel.Tab) {
        guard index >= total - prefetchLookahead else { return }
        Task {
            if kind == .allVideos {
                await model.loadMoreVideos(sort: videoSort)
            } else {
                await model.loadMore(for: kind)
            }
        }
    }

    private func canLoadMore(kind: ChannelViewModel.Tab) -> Bool {
        kind == .allVideos
            ? model.canLoadMoreVideos(sort: videoSort)
            : model.canLoadMore(for: kind)
    }

    private func loadingFooter(kind: ChannelViewModel.Tab) -> some View {
        ProgressView("Loading more…")
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .onAppear {
                Task {
                    if kind == .allVideos {
                        await model.loadMoreVideos(sort: videoSort)
                    } else {
                        await model.loadMore(for: kind)
                    }
                }
            }
    }

    // MARK: - Formatting

    private func channelStats(_ channel: Channel) -> String {
        var values: [String] = []
        if let subscribers = channel.subscriberCount {
            values.append("\(formattedCount(subscribers)) subscribers")
        }
        if let videos = channel.videoCount {
            values.append("\(formattedCount(videos)) videos")
        }
        return values.joined(separator: " · ")
    }

    private func channelURL(_ channel: Channel) -> URL? {
        URL(string: "https://www.youtube.com/channel/\(channel.id)")
    }

    private func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

// MARK: - Layout probes

// MARK: - Scroll tracking

/// Reads the pager's live offset and page width from the scroll view itself.
///
/// The `GeometryReader` probes these replace live in the *content* of a scroll view, and a probe
/// placed in the background of a lazy stack is not reliably re-evaluated as that stack scrolls —
/// which is why the underline sat still under the first tab while the selection moved. Scroll
/// geometry is reported by the scroll view directly, so there is nothing to miss an update.
/// Adding the content insets makes the value read zero at rest rather than minus the inset.
@available(iOS 17.0, *)
private struct PagerScrollGeometry: ViewModifier {
    @Binding var offset: CGFloat
    @Binding var width: CGFloat
    @Binding var height: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x + geometry.contentInsets.leading
                } action: { _, new in
                    offset = new
                }
                .onScrollGeometryChange(for: CGSize.self) { geometry in
                    geometry.containerSize
                } action: { _, new in
                    width = new.width
                    height = new.height
                }
        } else {
            content
        }
    }
}

/// A request for one page to put itself at a given vertical offset.
///
/// The token is what makes a repeat of the same offset a new request, and it is also how a page
/// that was created *after* the request was issued — the usual case, since the pager is lazy and
/// the neighbour is built as it slides in — knows to apply it on appear without re-applying an
/// old one later.
private struct PageScrollTarget: Equatable {
    var y: CGFloat
    var token: Int
}

@available(iOS 17.0, *)
private struct PageScrollAlignment: ViewModifier {
    let request: PageScrollTarget?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            PageScrollAlignmentBody(request: request, content: content)
        } else {
            // iOS 17 has no way to set a scroll view's offset to an arbitrary value, so the header
            // falls back to interpolating toward the incoming page instead of the page moving.
            content
        }
    }
}

@available(iOS 18.0, *)
private struct PageScrollAlignmentBody<Content: View>: View {
    let request: PageScrollTarget?
    let content: Content

    @State private var position = ScrollPosition()
    @State private var appliedToken = 0

    var body: some View {
        content
            .scrollPosition($position)
            .onAppear(perform: apply)
            .onChange(of: request) { _, _ in apply() }
    }

    private func apply() {
        guard let request, request.token > appliedToken else { return }
        appliedToken = request.token
        // Unanimated on purpose: this page is off screen or a sliver wide, and the whole point is
        // that the move is never seen.
        position.scrollTo(y: request.y)
    }
}

/// Same idea for a single page's vertical offset, which drives the header collapse.
@available(iOS 17.0, *)
private struct PageScrollGeometry: ViewModifier {
    let tab: String
    @Binding var offsets: [String: CGFloat]

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, new in
                offsets[tab] = new
            }
        } else {
            content
        }
    }
}

// MARK: - Preference keys

/// Live horizontal offset of the pager, which drives the underline.
struct ChannelPagerOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Width of a single page, used to turn the pager offset into a fractional page position.
struct ChannelPageWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Vertical scroll offset of each page, keyed by tab id. Drives the header collapse and the
/// navigation-bar title hand-off.
struct ChannelPageOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ChannelHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChannelTabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Measured frame of each tab label, keyed by `ChannelProfileTab.id`.
struct ChannelTabFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
