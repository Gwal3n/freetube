import SwiftUI

@available(iOS 17.0, *)
struct SubscriptionFeedScreen: View {
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(AppVisitState.self) private var appVisitState
    @State private var model = SubscriptionFeedViewModel()
    @State private var groups = LocalSubscriptionGroupStore.shared
    @State private var path: [AppNavigationRequest.Destination] = []
    @State private var handledNavigationRequestID: UUID?
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @AppStorage("largeSubscriptionFeedThumbnails") private var largeVideoThumbnails = false
    @AppStorage("showNewSubscriptionUploads") private var showNewSubscriptionUploads = true
    @State private var currentDate = Date.now
    @State private var lastAutomaticLoadKey: String?
    @State private var failedChannelsExpanded = false
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !groups.groups.isEmpty {
                    groupPicker
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if model.isRefreshing || model.lastRefreshAt != nil {
                    FeedRefreshProgress(model: model, referenceDate: currentDate)
                }
                if model.failedChannelCount > 0 && !model.isRefreshWarningDismissed {
                    Section {
                        refreshWarning
                    }
                }

                ForEach(model.videos) { video in
                    feedRow(video)
                }

                if model.canLoadMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        Group {
                            if model.isLoadingMore {
                                ProgressView()
                            } else {
                                Label("Load more", systemImage: "chevron.down")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(model.isLoadingMore || model.isRefreshing)
                    .id(automaticLoadKey)
                    .onAppear {
                        guard !model.isRefreshing,
                              lastAutomaticLoadKey != automaticLoadKey else { return }
                        lastAutomaticLoadKey = automaticLoadKey
                        Task { await model.loadMore() }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Feed")
            .toolbar {
                if !groups.groups.isEmpty {
                    ToolbarTitleMenu {
                        groupMenuActions
                    }
                }
            }
            .navigationDestination(for: AppNavigationRequest.Destination.self) { destination in
                switch destination {
                case .channel(let id):
                    ChannelScreen(channelID: id)
                        .onAppear { log.info("Feed channel destination appeared") }
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            .refreshable { await model.refresh() }
            .overlay {
                if !model.hasLoaded {
                    MediaListPlaceholder()
                } else if !model.hasSubscriptions && model.videos.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "rectangle.stack.person.crop",
                        description: Text("Channels you subscribe to locally will appear here.")
                    )
                } else if model.videos.isEmpty && model.didLastRefreshCompletelyFail {
                    ContentUnavailableView {
                        Label("Unable to Refresh", systemImage: "wifi.exclamationmark")
                    } description: {
                        VStack(spacing: 6) {
                            Text("Your subscriptions couldn’t be refreshed. Check your connection and try again.")
                            Text(verbatim: model.failedChannels.map(\.name).joined(separator: ", "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    } actions: {
                        Button("Try Again") {
                            Task { await model.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if model.videos.isEmpty && !model.isRefreshing {
                    if model.selectedGroupID != nil {
                        ContentUnavailableView(
                            "No videos in this group",
                            systemImage: "rectangle.stack",
                            description: Text("Add subscribed channels to this group or pull down to refresh.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Nothing new",
                            systemImage: "rectangle.stack",
                            description: Text("Pull down to refresh your subscriptions.")
                        )
                    }
                } else if model.videos.isEmpty && model.isRefreshing {
                    MediaListPlaceholder()
                        .padding(.top, 44)
                }
            }
            .task { await model.load() }
            .onChange(of: groups.groups) { _, _ in
                Task { await model.groupsChanged() }
            }
            .onChange(of: model.failedChannels) { _, _ in
                failedChannelsExpanded = false
            }
            .task {
                while !Task.isCancelled {
                    // A single clock for the feed keeps cached upload ages current while it is open.
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { break }
                    currentDate = .now
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { currentDate = .now }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task { await model.refreshProgress() }
            }
            .onChange(of: navigationRouter.feed?.id, initial: true) { _, _ in
                guard let request = navigationRouter.feed,
                      request.id != handledNavigationRequestID else { return }
                handledNavigationRequestID = request.id
                log.info("Feed received player destination; appending to navigation path")
                path.append(request.destination)
                navigationRouter.feed = nil
            }
        }
    }

    private var automaticLoadKey: String {
        "\(model.selectedGroupID?.uuidString ?? "all"):\(model.videos.count)"
    }

    /// A feed-only, best-effort marker. YouTube supplies relative upload ages rather than an
    /// exact timestamp, so rows without an estimated publish date remain unmarked.
    private func isNewSinceLastVisit(_ video: Video) -> Bool {
        guard showNewSubscriptionUploads,
              let previousVisitAt = appVisitState.previousVisitAt,
              let publishedAt = video.publishedAt else { return false }
        return publishedAt > previousVisitAt && publishedAt <= currentDate
    }

    private var refreshWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(model.failedChannelCount) \(model.failedChannelCount == 1 ? "channel" : "channels") couldn’t be refreshed. Cached videos were kept.")
                    .appFont(.footnote)
                if model.failedChannelCount == 1, let channel = model.failedChannels.first {
                    Text(verbatim: channel.name)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                } else if model.failedChannelCount > 1 {
                    DisclosureGroup("Affected channels", isExpanded: $failedChannelsExpanded) {
                        ForEach(model.failedChannels) { channel in
                            Text(verbatim: channel.name)
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .appFont(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.dismissRefreshWarning()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, 4)
    }

    /// A quiet subtitle beneath the native large title. It scrolls with the feed; the native
    /// title menu above remains available after the navigation bar collapses.
    private var groupPicker: some View {
        Menu {
            groupMenuActions
        } label: {
            HStack(spacing: 5) {
                Group {
                    if let groupName = model.selectedGroupName {
                        Text(verbatim: groupName)
                    } else {
                        Text("All subscriptions")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose feed group")
        .accessibilityValue(model.selectedGroupName ?? "All subscriptions")
    }

    @ViewBuilder
    private var groupMenuActions: some View {
        Button {
            Task { await model.selectGroup(nil) }
        } label: {
            if model.selectedGroupID == nil { Label("All subscriptions", systemImage: "checkmark") }
            else { Text("All subscriptions") }
        }
        ForEach(groups.groups) { group in
            Button {
                Task { await model.selectGroup(group.id) }
            } label: {
                if model.selectedGroupID == group.id { Label(group.name, systemImage: "checkmark") }
                else { Text(group.name) }
            }
        }
        Divider()
        Button {
            NotificationCenter.default.post(name: .freetubeOpenSubscriptionGroups, object: nil)
        } label: {
            Label("Manage groups", systemImage: "square.stack.3d.up")
        }
    }

    @ViewBuilder
    private func feedRow(_ video: Video) -> some View {
        if largeVideoThumbnails {
            VideoCard(
                video: video,
                onTap: { player.load(video) },
                showsMoreMenu: true,
                offersPlayNext: true,
                playbackProgress: showHistoryProgressBars ? model.playbackProgress[video.id] : nil,
                isNewSinceLastVisit: isNewSinceLastVisit(video),
                relativeDateReference: currentDate
            )
            .padding(.top, 4)
            .padding(.bottom, 14)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    player.enqueue(video)
                } label: {
                    Label("Add to queue", systemImage: "text.badge.plus")
                }
                .tint(.indigo)
            }
        } else {
            VideoRow(
                video: video,
                accessory: .actions(offersPlayNext: true),
                playbackProgress: showHistoryProgressBars ? model.playbackProgress[video.id] : nil,
                isNewSinceLastVisit: isNewSinceLastVisit(video),
                relativeDateReference: currentDate
            ) {
                player.load(video)
            }
        }
    }
}
