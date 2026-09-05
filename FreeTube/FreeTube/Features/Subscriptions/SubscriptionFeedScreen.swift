import SwiftUI

@available(iOS 17.0, *)
struct SubscriptionFeedScreen: View {
    @State private var model = SubscriptionFeedViewModel()
    @Environment(PlayerStateManager.self) private var player

    var body: some View {
        NavigationStack {
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
                        playbackProgress: model.playbackProgress[video.id]
                    ) {
                        player.load(video)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 8))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Feed")
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
        }
    }
}
