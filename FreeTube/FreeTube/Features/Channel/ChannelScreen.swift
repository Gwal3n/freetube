import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct ChannelScreen: View {
    @State private var model: ChannelViewModel
    @State private var blocklist = VideoBlocklist.shared
    @State private var pagerState = ChannelPagerState()
    @State private var videoSort: ChannelVideoSort = .newest
    @State private var showingGroupPicker = false
    @AppStorage("showChannelShortsTab") private var showShortsTab = true
    @AppStorage("showChannelLiveTab") private var showLiveTab = true
    @AppStorage("showChannelPlaylistsTab") private var showPlaylistsTab = true
    @AppStorage("showChannelAboutTab") private var showAboutTab = true

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
            MediaStyle.pageBackground.ignoresSafeArea()

            if let details = model.details {
                pager(details)
                header(details)
                if pagerState.showsNavigationTitle {
                    navigationBarBackdrop
                }
            } else if model.isLoading {
                ChannelProfilePlaceholder(headerOffset: pagerState.headerOffset)
            } else {
                ContentUnavailableView {
                    Label(
                        model.initialLoadFailed ? "Unable to Load Channel" : "Channel Not Loaded",
                        systemImage: model.initialLoadFailed ? "wifi.exclamationmark" : "person.crop.circle"
                    )
                } description: {
                    Text(model.initialLoadFailed
                         ? "The channel could not be loaded. Try again."
                         : "Loading was interrupted. Try again.")
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle(pagerState.showsNavigationTitle ? (model.details?.channel.name ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            channelActionsToolbar
        }
        // The system bar stays transparent: iOS 26 renders even a solid toolbar background as gray
        // glass. `navigationBarBackdrop` paints the opaque page color behind it instead.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load() }
        .onChange(of: model.details?.channel.id, initial: true) { _, _ in
            if let channel = model.details?.channel { RecentChannel.record(channel) }
        }
        .onChange(of: currentTabs) { _, tabs in
            pagerState.updateTabs(tabs)
        }
        .sheet(isPresented: $showingGroupPicker) {
            if let channel = model.details?.channel, channel.isSubscribed {
                ChannelGroupPickerSheet(channel: channel)
            }
        }
        .task(id: videoSort) {
            guard model.details != nil, videoSort != .newest else { return }
            await model.loadVideos(sort: videoSort)
        }
        .errorToast(Bindable(model).errorState)
    }

    /// Zero-height view at the top of the safe area whose background extends up through the
    /// navigation bar and status bar, covering the collapsed header with the same opaque color
    /// as the pinned tab bar.
    private var navigationBarBackdrop: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .background(MediaStyle.pageBackground.ignoresSafeArea(edges: .top))
            .allowsHitTesting(false)
    }

    // MARK: - Pager bridge

    private var currentTabs: [ChannelProfileTab] {
        model.details.map(availableTabs(for:)) ?? []
    }

    /// Tapping a tab writes the selection and moves the pager; swiping the pager writes it back.
    private var pagerSelection: Binding<String?> {
        Binding(
            get: { pagerState.selectedTab.id },
            set: { newValue in
                guard let newValue,
                      let tab = ChannelProfileTab(rawValue: newValue),
                      tab != pagerState.selectedTab else { return }
                pagerState.selectedTab = tab
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
        .modifier(HiddenTopScrollEdgeEffect())
        .coordinateSpace(name: Self.pagerSpace)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ChannelPageWidthKey.self, value: geometry.size.width)
            }
        }
        // Consumed only where the exact API below is unavailable, so the two never fight.
        .onPreferenceChange(ChannelPagerOffsetKey.self) { value in
            if #unavailable(iOS 18.0) { pagerState.pagerOffset = value }
        }
        .onPreferenceChange(ChannelPageWidthKey.self) { value in
            if #unavailable(iOS 18.0) { pagerState.pageWidth = value }
        }
        .modifier(PagerScrollGeometry(state: pagerState))
        .onChange(of: pagerState.isPagingActive) { _, active in
            if active { pagerState.alignPages(currentTabs, excluding: pagerState.selectedTab) }
        }
    }

    private func page(_ details: ChannelDetails, tab: ChannelProfileTab) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                // Reserves the header's footprint, plus a little air so the first row isn't
                // crowded against the tab bar. The header is drawn over the top of this.
                Color.clear.frame(height: pagerState.headerTotalHeight + ChannelProfileMetrics.contentTopInset)
                // Reserve only enough content for the header to collapse. A full viewport here
                // adds the tab bar and top inset again, letting short tabs scroll into blank space.
                channelContent(details, tab: tab)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ChannelPagerState.minimumPageContentHeight(
                            viewport: pagerState.pageViewportHeight, tabBar: pagerState.tabBarHeight,
                            topInset: ChannelProfileMetrics.contentTopInset
                        ),
                        alignment: .topLeading
                    )
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
        .modifier(HiddenTopScrollEdgeEffect())
        .coordinateSpace(name: Self.pageSpace(tab))
        .refreshable {
            await model.refresh(activeSort: tab == .videos ? videoSort : .newest)
        }
        .onPreferenceChange(ChannelPageOffsetKey.self) { offsets in
            if #unavailable(iOS 18.0) {
                pagerState.pageOffsets.merge(offsets) { _, new in new }
            }
        }
        .modifier(PageScrollGeometry { pagerState.handlePageScroll(tab: tab, offset: $0) })
        .modifier(PageScrollAlignment(request: pagerState.pageScrollTargets[tab.id]))
    }

    private static func pageSpace(_ tab: ChannelProfileTab) -> String {
        "channelPage-\(tab.id)"
    }

    // MARK: - Header

    private func header(_ details: ChannelDetails) -> some View {
        VStack(spacing: 0) {
            ChannelProfileHeader(
                channel: details.channel,
                statsText: channelStats(details.channel),
                headerOffset: pagerState.headerOffset,
                onToggleSubscribe: { Task { await model.toggleSubscribe() } }
            )
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChannelHeaderHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
            ChannelProfileTabBar(
                tabs: availableTabs(for: details),
                selectedTab: pagerState.selectedTab,
                pagePosition: pagerState.pagePosition,
                reduceMotion: reduceMotion,
                onSelect: selectTab
            )
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
        .background(MediaStyle.pageBackground)
        .offset(y: -pagerState.headerOffset)
        .onPreferenceChange(ChannelHeaderHeightKey.self) { pagerState.headerContentHeight = $0 }
        .onPreferenceChange(ChannelTabBarHeightKey.self) { pagerState.tabBarHeight = $0 }
    }

    @ToolbarContentBuilder
    private var channelActionsToolbar: some ToolbarContent {
        if model.details?.channel.isSubscribed == true {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingGroupPicker = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pagerState.showsNavigationTitle ? Color.primary : Color.white)
                }
                .accessibilityLabel("Add channel to group")
            }
        }
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
                    Divider()
                    Button {
                        if blocklist.blocks(channel) {
                            blocklist.unblock(channel)
                        } else {
                            blocklist.block(channel)
                        }
                    } label: {
                        Label(blocklist.blocks(channel) ? "Unblock channel" : "Block channel",
                              systemImage: blocklist.blocks(channel) ? "hand.raised.slash" : "hand.raised")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pagerState.showsNavigationTitle ? Color.primary : Color.white)
                }
                .accessibilityLabel("Channel actions")
            }
        }
    }

    // MARK: - Tabs

    private func availableTabs(for details: ChannelDetails) -> [ChannelProfileTab] {
        var tabs: [ChannelProfileTab] = [.videos]
        if showShortsTab, !blocklist.hideShorts,
           (!details.shorts.items.isEmpty || details.shorts.continuationToken != nil) {
            tabs.append(.shorts)
        }
        if showLiveTab, !details.directs.items.isEmpty { tabs.append(.live) }
        if showPlaylistsTab { tabs.append(.playlists) }
        if showAboutTab { tabs.append(.about) }
        return tabs
    }

    private func selectTab(_ tab: ChannelProfileTab) {
        // Before the pager moves, not after — the destination has to already be at the header's
        // height by the time it slides into view.
        pagerState.alignPages(currentTabs, excluding: pagerState.selectedTab)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
            pagerState.selectedTab = tab
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
                        .foregroundStyle(Color.primary)
                }
                .tint(Color.primary)
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
        let visibleVideos = videos.filter { !blocklist.blocks($0) }
        if visibleVideos.isEmpty && canLoadMore(kind: kind) {
            Button("Load more videos") {
                Task {
                    if kind == .allVideos {
                        await model.loadMoreVideos(sort: videoSort)
                    } else {
                        await model.loadMore(for: kind)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        } else if visibleVideos.isEmpty {
            ContentUnavailableView(videos.isEmpty ? emptyTitle : "No Unblocked Videos", systemImage: "play.rectangle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(visibleVideos.enumerated()), id: \.element.id) { index, video in
                    // No tap suppression needed any more: the enclosing scroll views cancel
                    // touches in their subviews once a scroll begins, so a swipe can no longer
                    // arrive here as a tap.
                    VideoRow(video: video, accessory: .actions(offersPlayNext: true)) {
                        player.load(video)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .onAppear { prefetchIfNeeded(index: index, total: visibleVideos.count, kind: kind) }
                }
                if canLoadMore(kind: kind) { loadingFooter(kind: kind) }
            }
        }
    }

    @ViewBuilder
    private func playlistRows(_ playlists: [Playlist]) -> some View {
        let visiblePlaylists = playlists.filter { !blocklist.blocks($0) }
        if visiblePlaylists.isEmpty && model.canLoadMore(for: .playlists) {
            Button("Load more playlists") {
                Task { await model.loadMore(for: .playlists) }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        } else if visiblePlaylists.isEmpty {
            ContentUnavailableView("No Playlists", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(visiblePlaylists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink {
                        PlaylistScreen(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .onAppear { prefetchIfNeeded(index: index, total: visiblePlaylists.count, kind: .playlists) }
                }
                if model.canLoadMore(for: .playlists) { loadingFooter(kind: .playlists) }
            }
        }
    }

    private func aboutSection(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").appFont(.title3, weight: .semibold)
                Text(aboutDescription(for: channel))
                    .appFont(.body)
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
    let state: ChannelPagerState

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x + geometry.contentInsets.leading
                } action: { _, new in
                    state.pagerOffset = new
                }
                .onScrollGeometryChange(for: CGSize.self) { geometry in
                    geometry.containerSize
                } action: { _, new in
                    state.pageWidth = new.width
                    state.pageViewportHeight = new.height
                }
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
private struct PageScrollAlignment: ViewModifier {
    let request: ChannelPageScrollTarget?

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
    let request: ChannelPageScrollTarget?
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
    let onScroll: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                ChannelPagerState.normalizedPageOffset(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, new in
                onScroll(new)
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

/// iOS 26 draws a gray blur under the navigation bar where content scrolls beneath it. The
/// channel header and pinned tab bar are opaque page background, so suppress it to keep the
/// whole top region one solid color.
private struct HiddenTopScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
