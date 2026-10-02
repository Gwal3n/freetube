import SwiftUI

@available(iOS 17.0, *)
struct SubscriptionFeedScreen: View {
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var model = SubscriptionFeedViewModel()
    @State private var groups = LocalSubscriptionGroupStore.shared
    @State private var showingGroups = false
    @State private var path: [AppNavigationRequest.Destination] = []
    @State private var handledNavigationRequestID: UUID?
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @AppStorage("largeSubscriptionFeedThumbnails") private var largeVideoThumbnails = false
    @State private var currentDate = Date.now
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.isRefreshing || model.lastRefreshAt != nil {
                    FeedRefreshProgress(model: model, referenceDate: currentDate)
                }
                if model.failedChannelCount > 0 {
                    Section {
                        Label(
                            "\(model.failedChannelCount) \(model.failedChannelCount == 1 ? "channel" : "channels") couldn’t be refreshed. Cached videos were kept.",
                            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(model.videos) { video in
                    feedRow(video)
                }

                if model.canLoadMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        Label("Load more", systemImage: "chevron.down")
                            .frame(maxWidth: .infinity)
                    }
                }

                if player.miniPlayerVisible && !player.fullScreenPresented {
                    Color.clear
                        .frame(height: 66)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                            showingGroups = true
                        } label: {
                            Label("Manage groups", systemImage: "square.stack.3d.up")
                        }
                    } label: {
                        Label(model.selectedGroupName ?? "All subscriptions", systemImage: "line.3.horizontal.decrease")
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
                        Text("Your subscriptions couldn’t be refreshed. Check your connection and try again.")
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
            .sheet(isPresented: $showingGroups) {
                SubscriptionGroupsScreen()
            }
            .onChange(of: groups.groups) { _, _ in
                Task { await model.groupsChanged() }
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

    @ViewBuilder
    private func feedRow(_ video: Video) -> some View {
        if largeVideoThumbnails {
            VideoCard(
                video: video,
                onTap: { player.load(video) },
                showsMoreMenu: true,
                offersPlayNext: true,
                playbackProgress: showHistoryProgressBars ? model.playbackProgress[video.id] : nil,
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
                relativeDateReference: currentDate
            ) {
                player.load(video)
            }
        }
    }
}
