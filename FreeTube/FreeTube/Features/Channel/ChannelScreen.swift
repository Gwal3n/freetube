import SwiftUI
import Kingfisher
import UIKit

@available(iOS 17.0, *)
struct ChannelScreen: View {
    @State private var model: ChannelViewModel
    @State private var selectedTab: ChannelProfileTab = .videos
    @State private var videoSort: ChannelVideoSort = .newest
    @GestureState private var tabDragOffset: CGFloat = 0
    @Namespace private var tabSelection
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let prefetchLookahead = 5

    init(channelID: String) {
        _model = State(wrappedValue: ChannelViewModel(channelID: channelID))
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let details = model.details {
                        channelHeader(details.channel)
                        channelTabBar(details)
                        interactiveChannelContent(details, width: viewport.size.width)
                    } else {
                        channelHeaderPlaceholder
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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
                    Image(systemName: "ellipsis")
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
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

            HStack(alignment: .top, spacing: 14) {
                KFImage(channel.thumbnailURL)
                    .thumbnail(size: CGSize(width: 88, height: 88)) {
                        Circle().fill(MediaStyle.placeholderFill)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 3))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if let handle = channel.handle, !handle.isEmpty {
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !channelStats(channel).isEmpty {
                        Text(channelStats(channel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                subscribeButton(channel)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let description = channel.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Button {
                    selectTab(.about)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .accessibilityHint("Opens the About tab")
            }
        }
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(availableTabs(for: details)) { tab in
                        Button {
                            selectTab(tab)
                        } label: {
                            VStack(spacing: 7) {
                                Text(tab.title)
                                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.55))
                                ZStack {
                                    Color.clear.frame(height: 2)
                                    if selectedTab == tab {
                                        Capsule().fill(.white)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "channel-tab", in: tabSelection)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedTab) { _, tab in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
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
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.35,
                      abs(value.predictedEndTranslation.width) > 80,
                      let currentIndex = availableTabs.firstIndex(of: selectedTab) else { return }
                let direction = value.predictedEndTranslation.width < 0 ? 1 : -1
                let destination = currentIndex + direction
                guard availableTabs.indices.contains(destination) else { return }
                selectTab(availableTabs[destination])
            }
    }

    @ViewBuilder
    private func interactiveChannelContent(_ details: ChannelDetails, width: CGFloat) -> some View {
        let tabs = availableTabs(for: details)
        let currentIndex = tabs.firstIndex(of: selectedTab) ?? 0
        let destinationIndex = tabDragOffset < 0 ? currentIndex + 1 : currentIndex - 1
        let hasDestination = tabDragOffset != 0 && tabs.indices.contains(destinationIndex)

        channelContent(details, tab: selectedTab)
            .frame(width: width)
            .offset(x: hasDestination ? tabDragOffset : resistedTabOffset(tabDragOffset))
            .overlay(alignment: .topLeading) {
                if hasDestination {
                    channelContent(details, tab: tabs[destinationIndex])
                        .frame(width: width)
                        .offset(x: (tabDragOffset < 0 ? width : -width) + tabDragOffset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Text("Videos").font(.headline)
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
            .padding(.vertical, 12)

            if videos.isEmpty,
               (!model.hasLoadedVideos(for: videoSort) || model.isLoadingVideos(for: videoSort)) {
                MediaListPlaceholder().padding(.horizontal, 16)
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
            LazyVStack(spacing: 0) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoCard(
                        video: video,
                        onTap: { player.load(video) },
                        showsMoreMenu: true,
                        offersPlayNext: true
                    )
                    .padding(.top, 4)
                    .padding(.bottom, 14)
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
            LazyVStack(spacing: 0) {
                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                    playlistCard(playlist)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
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

    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                PlaylistScreen(playlistID: playlist.id)
            } label: {
                KFImage(playlist.thumbnailURL)
                    .thumbnail(size: CGSize(width: 720, height: 405)) {
                        MediaStyle.placeholderFill
                    }
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .buttonStyle(ResponsiveButtonStyle())

            HStack(alignment: .top, spacing: 10) {
                NavigationLink {
                    PlaylistScreen(playlistID: playlist.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.title)
                            .font(MediaStyle.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(playlistMetadata(playlist))
                            .font(MediaStyle.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())

                PlaylistMoreActionsMenu(playlist: playlist)
            }
            .padding(.horizontal, MediaStyle.cardHorizontalPadding)
        }
    }

    private func playlistMetadata(_ playlist: Playlist) -> String {
        var parts: [String] = []
        if let channelName = playlist.channelName, !channelName.isEmpty { parts.append(channelName) }
        if let videoCount = playlist.videoCount { parts.append("\(videoCount) videos") }
        return parts.joined(separator: " · ")
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
