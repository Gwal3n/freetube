import SwiftUI

/// Device-local library following NewPipe's account-free model. Remote channel and playlist
/// destinations remain available when linked from other parts of the app, but this root owns
/// only history, subscriptions, and playlists persisted on this device.
@available(iOS 17.0, *)
struct LibraryScreen: View {
    private enum Destination: Hashable {
        case history
        case subscriptions
        case playlists
        case channel(String)
        case playlist(String)
        case localPlaylist(String)
    }

    let navigationRequest: AppNavigationRequest?
    var settingsRequest: Int = 0
    @State private var localHistoryCount: Int?
    @State private var localSubscriptions = LocalSubscriptionStore.shared
    @State private var localPlaylistCount: Int?
    @State private var path: [Destination] = []
    @State private var didLoadRootData = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                localHistorySection
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .history: LocalHistoryScreen()
                case .subscriptions: LocalSubscriptionsScreen()
                case .playlists: LocalPlaylistsScreen()
                case .channel(let id): ChannelScreen(channelID: id)
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            // Tie cold-start work to the visible root. A first navigation push cancels this task,
            // preventing late count/account mutations from invalidating the List mid-transition.
            .task(id: path.isEmpty) {
                guard path.isEmpty, !didLoadRootData else { return }
                await loadRootData()
            }
            .refreshable {
                localHistoryCount = await PersistenceWriter.shared.watchHistoryCount()
                localPlaylistCount = await localPlaylistCountFromStore()
            }
            // Present outside the list's refresh environment. Settings has no refresh action;
            // its downward gesture should belong to the system sheet instead.
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
                    .presentationDragIndicator(.hidden)
            }
            .onChange(of: settingsRequest, initial: true) { _, request in
                if request > 0 { showsSettings = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task {
                    let count = await PersistenceWriter.shared.watchHistoryCount()
                    guard path.isEmpty else { return }
                    localHistoryCount = count
                }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let destination = navigationRequest?.destination else { return }
                path.append(route(for: destination))
            }
            .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
                Task {
                    let count = await localPlaylistCountFromStore()
                    guard path.isEmpty else { return }
                    localPlaylistCount = count
                }
            }
        }
    }

    private func loadRootData() async {
        let historyCount = await PersistenceWriter.shared.watchHistoryCount()
        guard !Task.isCancelled, path.isEmpty else { return }
        let playlistCount = await localPlaylistCountFromStore()
        guard !Task.isCancelled, path.isEmpty else { return }
        localHistoryCount = historyCount
        localPlaylistCount = playlistCount

        didLoadRootData = true
    }

    private func localPlaylistCountFromStore() async -> Int {
        let playlists = await LocalPlaylistService().playlists()
        return playlists.count
    }

    private func route(for destination: AppNavigationRequest.Destination) -> Destination {
        switch destination {
        case .channel(let id): .channel(id)
        case .playlist(let id): .playlist(id)
        case .localPlaylist(let id): .localPlaylist(id)
        }
    }

    @ViewBuilder
    private var localHistorySection: some View {
        Section("On this device") {
            Button {
                path.append(.history)
            } label: {
                LibraryDestinationRow(
                    title: "Local history",
                    subtitle: countSubtitle(localHistoryCount, noun: "video"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .buttonStyle(.plain)

            Button {
                path.append(.subscriptions)
            } label: {
                LibraryDestinationRow(
                    title: "Local subscriptions",
                    subtitle: countSubtitle(localSubscriptions.subscriptions.count, noun: "channel"),
                    systemImage: "person.2.fill"
                )
            }
            .buttonStyle(.plain)

            Button {
                path.append(.playlists)
            } label: {
                LibraryDestinationRow(
                    title: "Local playlists",
                    subtitle: countSubtitle(localPlaylistCount, noun: "playlist"),
                    systemImage: "music.note.list"
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Builds the "N videos" / "N playlists" subtitle. When the library response hasn't
    /// returned yet (count is nil), we render "—" rather than a hardcoded "0" so the user can
    /// tell "still loading" from "actually empty".
    private func countSubtitle(_ count: Int?, noun: String) -> String {
        guard let count else { return "—" }
        let plural = count == 1 ? noun : noun + "s"
        return "\(count) \(plural)"
    }
}
