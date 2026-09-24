import SwiftUI
import Kingfisher
import UIKit

@available(iOS 17.0, *)
struct ChannelScreen: View {
    @State private var model: ChannelViewModel
    @State private var selectedTab: ChannelProfileTab = .videos
    @State private var videoSort: ChannelVideoSort = .newest
    @State private var suppressContentTap = false
    @GestureState private var tabDragOffset: CGFloat = 0
    @Namespace private var tabIndicatorNamespace
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let prefetchLookahead = 5

    init(channelID: String) {
        _model = State(wrappedValue: ChannelViewModel(channelID: channelID))
    }

    var body: some View {
        ScrollView {
            // Keep the profile shell eagerly mounted. The media collections remain
            // lazy in their individual sections.
            VStack(spacing: 0) {
                if let details = model.details {
                    channelHeader(details.channel)
                    channelTabBar(details)
                    interactiveChannelContent(details)
                } else {
                    channelHeaderPlaceholder
                }
            }
            // Hard clamp, and the reason the screen can't be widened from the inside again.
            // `maxWidth: .infinity` only *offers* to fill the proposal — a child that reports a
            // larger size (an image scaled to fill, a fixed-width row) still drags the stack out
            // with it, and `.clipped()` hides the overflow without correcting the reported size.
            // `containerRelativeFrame` pins this to the scroll view's width outright, so a
            // misbehaving child overflows and gets clipped instead of relaying its width to the
            // header and the tab bar.
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(model.details?.channel.name ?? "Channel")
        .toolbar { channelActionsToolbar }
        .task { await model.load() }
        .task(id: videoSort) {
            guard model.details != nil, videoSort != .newest else { return }
            await model.loadVideos(sort: videoSort)
        }
        .errorToast(Bindable(model).errorState)
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
    /// The indicator rides on `matchedGeometryEffect`, so its travel is derived from the laid-out
    /// labels rather than recomputed from segment arithmetic.
    private func channelTabBar(_ details: ChannelDetails) -> some View {
        let tabs = availableTabs(for: details)

        return ScrollView(.horizontal) {
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
                            // Only the selected tab carries the geometry id, so it is
                            // unambiguously the source and SwiftUI animates the single indicator
                            // between positions. Giving every tab the id and toggling `isSource`
                            // would snap the inactive ones onto the active frame instead.
                            if isSelected {
                                Capsule()
                                    .fill(Color.white)
                                    .frame(height: 2.5)
                                    .matchedGeometryEffect(id: "channelTabIndicator", in: tabIndicatorNamespace)
                            } else {
                                Color.clear.frame(height: 2.5)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func availableTabs(for details: ChannelDetails) -> [ChannelProfileTab] {
        var tabs: [ChannelProfileTab] = [.videos, .shorts]
        if !details.directs.items.isEmpty { tabs.append(.live) }
        tabs.append(contentsOf: [.playlists, .about])
        return tabs
    }

    private func selectTab(_ tab: ChannelProfileTab) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
            selectedTab = tab
        }
    }

    private func tabSwipeGesture(availableTabs: [ChannelProfileTab]) -> some Gesture {
        DragGesture(minimumDistance: 32)
            .updating($tabDragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                state = value.translation.width
            }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.15 else { return }
                suppressContentTap = true
            }
            .onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) * 1.35,
                   abs(value.predictedEndTranslation.width) > 80,
                   let currentIndex = availableTabs.firstIndex(of: selectedTab) {
                    let direction = value.predictedEndTranslation.width < 0 ? 1 : -1
                    let destination = currentIndex + direction
                    if availableTabs.indices.contains(destination) {
                        selectTab(availableTabs[destination])
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    suppressContentTap = false
                }
            }
    }

    @ViewBuilder
    private func interactiveChannelContent(_ details: ChannelDetails) -> some View {
        let tabs = availableTabs(for: details)
        let currentIndex = tabs.firstIndex(of: selectedTab) ?? 0
        let destinationIndex = tabDragOffset < 0 ? currentIndex + 1 : currentIndex - 1
        let hasDestination = tabDragOffset != 0 && tabs.indices.contains(destinationIndex)

        channelContent(details, tab: selectedTab)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .allowsHitTesting(!suppressContentTap)
            .offset(x: hasDestination ? tabDragOffset : resistedTabOffset(tabDragOffset))
            .overlay(alignment: .topLeading) {
                if hasDestination {
                    GeometryReader { geometry in
                        channelContent(details, tab: tabs[destinationIndex])
                            .frame(width: geometry.size.width, alignment: .topLeading)
                            .allowsHitTesting(false)
                            .offset(
                                x: (tabDragOffset < 0 ? geometry.size.width : -geometry.size.width)
                                    + tabDragOffset
                            )
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(tabSwipeGesture(availableTabs: tabs))
    }

    private func resistedTabOffset(_ offset: CGFloat) -> CGFloat {
        guard offset != 0 else { return 0 }
        return offset * 0.18
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
                    VideoRow(video: video, accessory: .actions(offersPlayNext: true)) {
                        guard !suppressContentTap else { return }
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
