import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct ChannelScreen: View {
    @State private var model: ChannelViewModel
    @State private var selectedTab: ChannelProfileTab = .videos
    @State private var videoSort: ChannelVideoSort = .newest
    @Namespace private var tabSelection
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let prefetchLookahead = 5

    init(channelID: String) {
        _model = State(wrappedValue: ChannelViewModel(channelID: channelID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let details = model.details {
                    channelHeader(details.channel)
                    Section {
                        channelContent(details)
                            .id(selectedTab)
                            .transition(.opacity)
                            .simultaneousGesture(tabSwipeGesture(availableTabs: availableTabs(for: details)))
                    } header: {
                        channelTabBar(details)
                    }
                } else {
                    channelHeaderPlaceholder
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(model.details?.channel.name ?? "Channel")
        .task { await model.load() }
        .task(id: videoSort) {
            guard model.details != nil, videoSort != .newest else { return }
            await model.loadVideos(sort: videoSort)
        }
        .errorToast(Bindable(model).errorState)
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
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 4))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                    .offset(y: -30)
                    .padding(.bottom, -30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    if let handle = channel.handle, !handle.isEmpty {
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                subscribeButton(channel)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if !channelStats(channel).isEmpty {
                Text(channelStats(channel))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if let description = channel.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Button {
                    selectTab(.about)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .accessibilityHint("Opens the About tab")
            }
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func banner(_ channel: Channel) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.42), Color.accentColor.opacity(0.12)],
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
        if channel.isSubscribed {
            Button {
                Task { await model.toggleSubscribe() }
            } label: {
                Label("Subscribed", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button {
                Task { await model.toggleSubscribe() }
            } label: {
                Text("Subscribe")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Tabs

    private func channelTabBar(_ details: ChannelDetails) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(availableTabs(for: details)) { tab in
                        Button {
                            selectTab(tab)
                        } label: {
                            Text(tab.title)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                                .padding(.horizontal, 13)
                                .frame(height: 34)
                                .background {
                                    if selectedTab == tab {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.09))
                                            .matchedGeometryEffect(id: "channel-tab", in: tabSelection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedTab) { _, tab in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
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

    // MARK: - Tab content

    @ViewBuilder
    private func channelContent(_ details: ChannelDetails) -> some View {
        switch selectedTab {
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
                    VideoRow(video: video, accessory: .actions(offersPlayNext: true)) {
                        player.load(video)
                    }
                    .padding(.horizontal, 16)
                    .onAppear { prefetchIfNeeded(index: index, total: videos.count, kind: kind) }
                    if index < videos.count - 1 {
                        Divider().padding(.leading, 176)
                    }
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
                    NavigationLink {
                        PlaylistScreen(playlistID: playlist.id)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .onAppear { prefetchIfNeeded(index: index, total: playlists.count, kind: .playlists) }
                    if index < playlists.count - 1 {
                        Divider().padding(.leading, 176)
                    }
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
                if let url = URL(string: "https://www.youtube.com/channel/\(channel.id)") {
                    Link(destination: url) {
                        Label("Open channel in browser", systemImage: "safari")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    private func formattedCount(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
