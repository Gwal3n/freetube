import SwiftUI

@available(iOS 17.0, *)
struct SubscriptionFeedScreen: View {
    let navigationRequest: AppNavigationRequest?
    @State private var model = SubscriptionFeedViewModel()
    @State private var path = NavigationPath()
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.isRefreshing {
                    HStack(spacing: 10) {
                        ProgressView(
                            value: Double(model.refreshedChannels),
                            total: Double(max(1, model.refreshChannelCount))
                        )
                        Text(verbatim: "\(model.refreshedChannels)/\(model.refreshChannelCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Refreshing subscriptions")
                    .accessibilityValue("\(model.refreshedChannels) of \(model.refreshChannelCount)")
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
                    VideoRow(
                        video: video,
                        showsMoreMenu: true,
                        offersPlayNext: true,
                        playbackProgress: showHistoryProgressBars ? model.playbackProgress[video.id] : nil
                    ) {
                        player.load(video)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(MediaStyle.listRowInsets)
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
            .navigationDestination(for: AppNavigationRequest.Destination.self) { destination in
                switch destination {
                case .channel(let id): ChannelScreen(channelID: id)
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
                    ContentUnavailableView(
                        "Nothing new",
                        systemImage: "rectangle.stack",
                        description: Text("Pull down to refresh your subscriptions.")
                    )
                } else if model.videos.isEmpty && model.isRefreshing {
                    MediaListPlaceholder()
                }
            }
            .task { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task { await model.refreshProgress() }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let destination = navigationRequest?.destination else { return }
                path.append(destination)
            }
        }
    }
}
