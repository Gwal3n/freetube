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
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 8))
                }

                if model.canLoadMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        Label("Load more", systemImage: "chevron.down")
                            .frame(maxWidth: .infinity)
                    }
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
                if !model.hasSubscriptions && model.videos.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "rectangle.stack.person.crop",
                        description: Text("Channels you subscribe to locally will appear here.")
                    )
                } else if model.videos.isEmpty && !model.isRefreshing {
                    ContentUnavailableView(
                        "Nothing new",
                        systemImage: "rectangle.stack",
                        description: Text("Pull down to refresh your subscriptions.")
                    )
                } else if model.videos.isEmpty && model.isRefreshing {
                    ProgressView("Refreshing subscriptions…")
                }
            }
            .task { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task { await model.load() }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let destination = navigationRequest?.destination else { return }
                path.append(destination)
            }
        }
    }
}
