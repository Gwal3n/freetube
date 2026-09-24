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
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var channelHeaderPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 178)
            HStack(spacing: 14) {
                Circle().fill(.quaternary).frame(width: 82, height: 82)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 180, height: 20)
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 120, height: 12)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading channel")
        .allowsHitTesting(false)
    }

    private func channelHeader(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            banner(channel)

            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    Circle().fill(.white.opacity(0.12))
                    Text(channel.name.prefix(1).uppercased())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    KFImage(channel.thumbnailURL)
                        .resizable()
                        .scaledToFill()
                }
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let handle = channel.handle, !handle.isEmpty {
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    if !channelStats(channel).isEmpty {
                        Text(channelStats(channel))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)
                subscribeButton(channel)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func banner(_ channel: Channel) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let bannerURL = channel.bannerURL {
                KFImage(bannerURL)
                    .thumbnail(size: CGSize(width: 900, height: 300)) {
                        Color.clear
                    }
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.20)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        // `maxWidth` before the height, and not optional. `scaledToFill` reports a size that
        // *covers* the proposal, so a 6:1 channel banner told only that it is 178pt tall reports
        // itself ~1075pt wide, and `clipped()` clips the drawing without shrinking that reported
        // size. The ZStack then hands it up to the header, the header to the root VStack, and every
        // `maxWidth: .infinity` below inherits a width wider than the screen — which is what threw
        // the subscribe button off the right edge and left the tab bar dividing a phantom width
        // into five. Pinning the width here keeps the overflow inside the banner where it belongs.
        .frame(maxWidth: .infinity)
        .frame(height: 178)
        .clipped()
        .accessibilityHidden(true)
    }

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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(channel.isSubscribed ? 0.10 : 0.16), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(ResponsiveButtonStyle())
    }

    // MARK: - Tabs

    private func channelTabBar(_ details: ChannelDetails) -> some View {
        GeometryReader { geometry in
            let tabs = availableTabs(for: details)
            let width = geometry.size.width
            let segmentWidth = width / CGFloat(max(1, tabs.count))
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let dragProgress = min(max(-tabDragOffset / max(1, width), -1), 1)
            let indicatorIndex = min(max(selectedIndex + dragProgress, 0), CGFloat(max(0, tabs.count - 1)))

            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        Button {
                            selectTab(tab)
                        } label: {
                            Text(tab.title)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.55))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: segmentWidth)
                    }
                }

                Capsule()
                    .fill(.white)
                    .frame(width: min(34, max(20, segmentWidth - 20)), height: 2.5)
                    .offset(
                        x: segmentWidth * indicatorIndex
                            + (segmentWidth - min(34, max(20, segmentWidth - 20))) / 2
                    )
            }
        }
        .frame(height: 46)
        .background(Color.black)
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
