import SwiftUI

@available(iOS 17.0, *)
struct SubscriptionFeedScreen: View {
    @Binding var selectedTab: RootView.Tab
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
    @AppStorage("feedWatchFilter") private var watchFilterRaw = FeedWatchFilter.all.rawValue
    @AppStorage("feedDurationFilter") private var durationFilterRaw = FeedDurationFilter.all.rawValue
    @AppStorage("feedCustomDurationMinimumMinutes") private var customMinimumMinutes = 0
    @AppStorage("feedCustomDurationMaximumMinutes") private var customMaximumMinutes = 60
    @AppStorage("automaticFeedRefreshEnabled") private var automaticFeedRefreshEnabled = false
    @AppStorage("automaticFeedRefreshInterval") private var automaticFeedRefreshIntervalRaw = FeedRefreshInterval.everySixHours.rawValue
    @State private var currentDate = Date.now
    @State private var lastAutomaticLoadKey: String?
    @State private var failedChannelsExpanded = false
    @State private var isCustomDurationPresented = false
    @State private var isWatchFilterPresented = false
    @State private var lastFilteredPrefetchKey: String?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                HStack(spacing: 12) {
                    if !groups.groups.isEmpty { groupPicker }
                    Spacer(minLength: 0)
                    filterMenu
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if model.isRefreshing || model.lastRefreshAt != nil {
                    FeedRefreshProgress(model: model, referenceDate: currentDate)
                }
                if model.failedChannelCount > 0 && !model.isRefreshWarningDismissed {
                    Section {
                        refreshWarning
                    }
                }

                ForEach(filteredVideos) { video in
                    feedRow(video)
                        .onAppear {
                            guard watchFilter != .all || durationFilter != .all,
                                  filteredVideos.count >= 12,
                                  filteredVideos.suffix(5).contains(where: { $0.id == video.id }),
                                  model.canLoadMore,
                                  !model.isLoadingMore,
                                  !model.isRefreshing else { return }
                            let key = automaticLoadKey
                            guard lastFilteredPrefetchKey != key else { return }
                            lastFilteredPrefetchKey = key
                            Task {
                                await model.loadMore()
                                await fillFilteredFeed()
                            }
                        }
                }

                if filteredVideos.isEmpty && !model.videos.isEmpty && model.canLoadMore {
                    Text(model.isLoadingMore
                         ? "Finding matching videos…"
                         : "No loaded videos match. Load more to check the next page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowSeparator(.hidden)
                }

                if model.canLoadMore {
                    Button {
                        Task {
                            await model.loadMore()
                            if watchFilter != .all || durationFilter != .all {
                                await fillFilteredFeed()
                            }
                        }
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
                        guard watchFilter == .all,
                              durationFilter == .all,
                              !model.isRefreshing,
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
            .sheet(isPresented: $isCustomDurationPresented) {
                FeedDurationRangeSheet(
                    minimumMinutes: customMinimumMinutes,
                    maximumMinutes: customMaximumMinutes
                ) { minimum, maximum in
                    customMinimumMinutes = minimum
                    customMaximumMinutes = maximum
                    durationFilterRaw = FeedDurationFilter.custom.rawValue
                }
            }
            .refreshable { await model.refresh() }
            .task(id: filteredFillKey) { await fillFilteredFeed() }
            .onChange(of: filteredFillKey) { _, _ in lastFilteredPrefetchKey = nil }
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
                } else if filteredVideos.isEmpty && !model.canLoadMore && !model.isRefreshing {
                    ContentUnavailableView {
                        Label("No matching videos", systemImage: "line.3.horizontal.decrease")
                    } description: {
                        Text("Try changing the Feed filters.")
                    } actions: {
                        Button("Reset Filters") {
                            watchFilterRaw = FeedWatchFilter.all.rawValue
                            durationFilterRaw = FeedDurationFilter.all.rawValue
                        }
                    }
                }
            }
            .task(id: automaticRefreshTaskKey) { await loadAndScheduleAutomaticRefresh() }
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
        "\(model.selectedGroupID?.uuidString ?? "all"):\(model.videos.count):\(watchFilterRaw):\(durationFilterRaw):\(customMinimumMinutes):\(customMaximumMinutes)"
    }

    private var filteredFillKey: String {
        "\(model.firstPageRevision):\(watchFilterRaw):\(durationFilterRaw):\(customMinimumMinutes):\(customMaximumMinutes)"
    }

    private var watchFilter: FeedWatchFilter {
        FeedWatchFilter(rawValue: watchFilterRaw) ?? .all
    }

    private var durationFilter: FeedDurationFilter {
        FeedDurationFilter(rawValue: durationFilterRaw) ?? .all
    }

    private var filteredVideos: [Video] {
        model.videos.filter { video in
            watchFilter.includes(model.watchStatuses[video.id])
                && durationFilter.includes(
                    video.duration,
                    minimumMinutes: customMinimumMinutes,
                    maximumMinutes: customMaximumMinutes
                )
        }
    }

    /// Feed pagination reads cached videos, but sparse filters still need several cache pages to
    /// show a useful first screen. Stop after a bounded batch; explicit Load more can continue it.
    private func fillFilteredFeed() async {
        let selectedWatch = watchFilter
        let selectedDuration = durationFilter
        let minimum = customMinimumMinutes
        let maximum = customMaximumMinutes
        guard selectedWatch != .all || selectedDuration != .all else { return }
        let revision = model.firstPageRevision
        let targetCount = 12
        let maximumPages = 10

        for _ in 0..<maximumPages {
            while model.isRefreshing || model.isLoadingMore {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            guard !Task.isCancelled,
                  model.firstPageRevision == revision,
                  watchFilter == selectedWatch,
                  durationFilter == selectedDuration,
                  customMinimumMinutes == minimum,
                  customMaximumMinutes == maximum,
                  model.canLoadMore else { return }
            let visibleCount = model.videos.filter { video in
                selectedWatch.includes(model.watchStatuses[video.id])
                    && selectedDuration.includes(
                        video.duration,
                        minimumMinutes: minimum,
                        maximumMinutes: maximum
                    )
            }.count
            if visibleCount >= targetCount { return }

            let previousCount = model.videos.count
            await model.loadMore()
            guard !Task.isCancelled, model.videos.count > previousCount else { return }
        }
    }

    private var filterMenu: some View {
        Menu {
            Button {
                isWatchFilterPresented = true
            } label: {
                Label("Watch status", systemImage: "eye")
            }
            Menu("Duration") {
                ForEach(FeedDurationFilter.allCases) { option in
                    Button {
                        if option == .custom {
                            isCustomDurationPresented = true
                        } else {
                            durationFilterRaw = option.rawValue
                        }
                    } label: {
                        if durationFilter == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            if watchFilter != .all || durationFilter != .all {
                Divider()
                Button("Reset Filters") {
                    watchFilterRaw = FeedWatchFilter.all.rawValue
                    durationFilterRaw = FeedDurationFilter.all.rawValue
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                if watchFilter != .all || durationFilter != .all {
                    Text("Filtered")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed filters")
        .accessibilityValue(watchFilter == .all && durationFilter == .all ? "Off" : "On")
        .popover(isPresented: $isWatchFilterPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Watch status")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                ForEach(FeedWatchFilter.allCases) { option in
                    Button {
                        watchFilterRaw = option.rawValue
                        isWatchFilterPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.title)
                            Spacer(minLength: 8)
                            if watchFilter == option {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    if option != FeedWatchFilter.allCases.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .frame(width: 270)
            .padding(.bottom, 6)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var automaticRefreshTaskKey: String {
        "\(selectedTab == .feed):\(scenePhase == .active):\(automaticFeedRefreshEnabled):\(automaticFeedRefreshIntervalRaw)"
    }

    /// Foreground, Feed-only timer. A manual pull-to-refresh moves the due time forward; a
    /// failed automatic attempt still waits one interval before retrying. Nothing is scheduled
    /// through BackgroundTasks and the timer stops when the tab or app becomes inactive.
    private func loadAndScheduleAutomaticRefresh() async {
        guard selectedTab == .feed, scenePhase == .active else { return }
        if !model.hasLoaded { await model.load() }
        guard automaticFeedRefreshEnabled, scenePhase == .active else { return }
        let interval = FeedRefreshInterval(rawValue: automaticFeedRefreshIntervalRaw) ?? .everySixHours
        while !Task.isCancelled {
            guard model.hasSubscriptions, !player.fullScreenPresented else {
                try? await Task.sleep(for: .seconds(60))
                continue
            }
            let mostRecent = max(model.lastRefreshAt ?? .distantPast, model.lastRefreshAttemptAt ?? .distantPast)
            if Date.now.timeIntervalSince(mostRecent) >= interval.seconds {
                await model.refresh()
            } else {
                try? await Task.sleep(for: .seconds(60))
            }
        }
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

private enum FeedWatchFilter: String, CaseIterable, Identifiable {
    case all, hideWatched, hidePartial, onlyPartial, onlyFinished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All videos"
        case .hideWatched: "Hide watched"
        case .hidePartial: "Hide partially watched"
        case .onlyPartial: "Only partially watched"
        case .onlyFinished: "Only finished"
        }
    }

    func includes(_ status: WatchHistoryStatus?) -> Bool {
        switch self {
        case .all: true
        case .hideWatched: status == nil
        case .hidePartial: status != .partial
        case .onlyPartial: status == .partial
        case .onlyFinished: status == .finished
        }
    }
}

private enum FeedDurationFilter: String, CaseIterable, Identifiable {
    case all, underFourMinutes, fourToTwentyMinutes, overTwentyMinutes, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Any length"
        case .underFourMinutes: "Under 4 minutes"
        case .fourToTwentyMinutes: "4–20 minutes"
        case .overTwentyMinutes: "Over 20 minutes"
        case .custom: "Custom range…"
        }
    }

    func includes(
        _ duration: TimeInterval?,
        minimumMinutes: Int,
        maximumMinutes: Int
    ) -> Bool {
        guard self != .all else { return true }
        guard let duration, duration.isFinite, duration > 0 else { return false }
        return switch self {
        case .all: true
        case .underFourMinutes: duration < 240
        case .fourToTwentyMinutes: duration >= 240 && duration <= 1200
        case .overTwentyMinutes: duration > 1200
        case .custom:
            duration >= TimeInterval(max(0, minimumMinutes)) * 60
                && (maximumMinutes == 0 || duration <= TimeInterval(maximumMinutes) * 60)
        }
    }
}
