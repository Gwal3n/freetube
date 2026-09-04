import SwiftUI

/// Dedicated destination for one submitted query. Back returns to Search's recent-search root;
/// pagination continues to update the shared model without rebuilding the native search field.
@available(iOS 17.0, *)
struct SearchResultsScreen: View {
    @Bindable var model: SearchViewModel
    let query: String
    @Environment(PlayerStateManager.self) private var player

    var body: some View {
        Group {
            if let results = model.results {
                resultsList(results)
            } else if model.isLoading {
                LoadingView()
            } else {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    message: "Try another search."
                )
            }
        }
        .navigationTitle(query)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.submit()
        }
        .errorToast($model.errorState)
    }

    private func resultsList(_ results: SearchResult) -> some View {
        List {
            if !results.channels.isEmpty {
                Section("Channels") {
                    ForEach(results.channels) { channel in
                        NavigationLink {
                            ChannelScreen(channelID: channel.id)
                        } label: {
                            ChannelRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(results.playlists) { playlist in
                        NavigationLink {
                            PlaylistScreen(playlistID: playlist.id)
                        } label: {
                            PlaylistRow(playlist: playlist, showsMoreMenu: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.videos.isEmpty {
                Section("Videos") {
                    let lookaheadIDs = Set(results.videos.suffix(5).map(\.id))
                    ForEach(results.videos) { video in
                        VideoRow(video: video, showsMoreMenu: true, offersPlayNext: true) {
                            player.load(video)
                        }
                        .onAppear {
                            guard lookaheadIDs.contains(video.id),
                                  results.continuationToken != nil,
                                  !model.isLoading else { return }
                            Task { await model.loadMore() }
                        }
                    }
                    if model.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
