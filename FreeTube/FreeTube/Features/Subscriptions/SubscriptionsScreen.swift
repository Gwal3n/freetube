import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct SubscriptionsScreen: View {
    @State private var model = SubscriptionsViewModel()
    @Environment(PlayerStateManager.self) private var player

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !model.channels.isEmpty {
                        SectionHeader(title: "Subscriptions")
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(model.channels) { channel in
                                    NavigationLink {
                                        ChannelScreen(channelID: channel.id)
                                    } label: {
                                        channelChip(channel)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    SectionHeader(title: "Latest from your subscriptions")
                        .padding(.horizontal)
                    ForEach(model.feedVideos) { video in
                        VideoCard(video: video, onTap: { player.load(video) }, showsMoreMenu: true)
                    }

                    if model.isLoading && model.feedVideos.isEmpty { subscriptionFeedPlaceholder }
                    if model.feedVideos.isEmpty && !model.isLoading {
                        ContentUnavailableView(
                            "Nothing New",
                            systemImage: "rectangle.stack.person.crop",
                            description: Text("Subscribe to channels to see their latest videos here.")
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Subscriptions")
            .refreshable { await model.load() }
            .task {
                if model.feedVideos.isEmpty { await model.load() }
            }
            .errorToast(Bindable(model).errorState)
        }
    }

    @ViewBuilder
    private func channelChip(_ channel: Channel) -> some View {
        VStack(spacing: 6) {
            KFImage(channel.thumbnailURL)
                .thumbnail(size: CGSize(width: 64, height: 64)) {
                    Circle().fill(MediaStyle.placeholderFill)
                }
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            Text(channel.name).font(.caption).lineLimit(1).frame(maxWidth: 80)
        }
    }

    private var subscriptionFeedPlaceholder: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous)
                        .fill(.quaternary)
                        .aspectRatio(16 / 9, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 13)
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 150, height: 9)
                }
            }
        }
        .padding(.horizontal)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading subscriptions")
    }
}
