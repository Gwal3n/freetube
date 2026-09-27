import SwiftUI

/// Device-local library following NewPipe's account-free model. Remote channel and playlist
/// destinations remain available when linked from other parts of the app, but this root owns
/// only history, subscriptions, and playlists persisted on this device.
@available(iOS 17.0, *)
struct LibraryScreen: View {
    private enum LocalDestination: String, Hashable {
        case history, subscriptions, playlists
    }

    let navigationRequest: AppNavigationRequest?
    var settingsRequest: Int = 0
    @State private var localHistoryCount: Int?
    @State private var localSubscriptions = LocalSubscriptionStore.shared
    @State private var localPlaylistCount: Int?
    @State private var path = NavigationPath()
    @State private var rootIsVisible = false
    @State private var didLoadRootData = false
    @State private var showsSettings = false
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack(path: navigationPathBinding) {
            List {
                localHistorySection
            }
            .navigationTitle("Library")
            .navigationDiagnostics("Library root list")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        log.info("Library Settings button tapped")
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: AppNavigationRequest.Destination.self) { destination in
                switch destination {
                case .channel(let id): ChannelScreen(channelID: id)
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            .navigationDestination(for: LocalDestination.self) { destination in
                switch destination {
                case .history:
                    LocalHistoryScreen().navigationDiagnostics("Library destination local history")
                case .subscriptions:
                    LocalSubscriptionsScreen().navigationDiagnostics("Library destination local subscriptions")
                case .playlists:
                    LocalPlaylistsScreen().navigationDiagnostics("Library destination local playlists")
                }
            }
            // Tie cold-start work to the visible root. A first navigation push cancels this task,
            // preventing late count/account mutations from invalidating the List mid-transition.
            .onAppear { rootIsVisible = true }
            .onDisappear { rootIsVisible = false }
            .task(id: rootIsVisible) {
                guard rootIsVisible, !didLoadRootData else { return }
                await loadRootData()
            }
            .refreshable {
                localHistoryCount = await PersistenceWriter.shared.watchHistoryCount()
                localPlaylistCount = await localPlaylistCountFromStore()
            }
            // Present outside the list's refresh environment. Settings has no refresh action;
            // its downward gesture should belong to the system sheet instead.
            .sheet(isPresented: $showsSettings, onDismiss: {
                log.info("Library Settings sheet dismissed")
            }) {
                SettingsScreen()
                    .navigationDiagnostics("Settings sheet stack")
                    .presentationDragIndicator(.hidden)
            }
            .onChange(of: showsSettings) { previous, current in
                log.info("Library Settings sheet binding: \(previous) → \(current)")
            }
            .onChange(of: settingsRequest, initial: true) { _, request in
                if request > 0 { showsSettings = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task {
                    let count = await PersistenceWriter.shared.watchHistoryCount()
                    guard rootIsVisible else { return }
                    localHistoryCount = count
                }
            }
            .onChange(of: navigationRequest?.id) { _, _ in
                guard let destination = navigationRequest?.destination else { return }
                log.info("Library external destination requested; depth=\(path.count)")
                path.append(destination)
            }
            .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
                Task {
                    let count = await localPlaylistCountFromStore()
                    guard rootIsVisible else { return }
                    localPlaylistCount = count
                }
            }
        }
        .onChange(of: path.count) { previous, current in
            log.info("Library path rendered: \(previous) → \(current)")
        }
    }

    private var navigationPathBinding: Binding<NavigationPath> {
        Binding(get: { path }, set: { updated in
            log.info("Library framework path write: \(path.count) → \(updated.count)")
            path = updated
        })
    }

    private func open(_ destination: LocalDestination) {
        log.info("Library action requested: \(destination.rawValue) depth=\(path.count)")
        path.append(destination)
        log.info("Library path appended: \(destination.rawValue) depth=\(path.count)")
    }

    private func loadRootData() async {
        let historyCount = await PersistenceWriter.shared.watchHistoryCount()
        guard !Task.isCancelled, rootIsVisible else { return }
        let playlistCount = await localPlaylistCountFromStore()
        guard !Task.isCancelled, rootIsVisible else { return }
        localHistoryCount = historyCount
        localPlaylistCount = playlistCount

        didLoadRootData = true
    }

    private func localPlaylistCountFromStore() async -> Int {
        let playlists = await LocalPlaylistService().playlists()
        return playlists.count
    }

    @ViewBuilder
    private var localHistorySection: some View {
        Section("On this device") {
            Button {
                open(.history)
            } label: {
                HStack {
                    LibraryDestinationRow(
                        title: "Local history",
                        subtitle: countSubtitle(localHistoryCount, noun: "video"),
                        systemImage: "clock.arrow.circlepath"
                    )
                    disclosureIndicator
                }
                .contentShape(Rectangle())
            }
            .tint(.white)
            .navigationDiagnostics("Library row local history")

            Button {
                open(.subscriptions)
            } label: {
                HStack {
                    LibraryDestinationRow(
                        title: "Local subscriptions",
                        subtitle: countSubtitle(localSubscriptions.subscriptions.count, noun: "channel"),
                        systemImage: "person.2.fill"
                    )
                    disclosureIndicator
                }
                .contentShape(Rectangle())
            }
            .tint(.white)
            .navigationDiagnostics("Library row local subscriptions")

            Button {
                open(.playlists)
            } label: {
                HStack {
                    LibraryDestinationRow(
                        title: "Local playlists",
                        subtitle: countSubtitle(localPlaylistCount, noun: "playlist"),
                        systemImage: "music.note.list"
                    )
                    disclosureIndicator
                }
                .contentShape(Rectangle())
            }
            .tint(.white)
            .navigationDiagnostics("Library row local playlists")
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
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
