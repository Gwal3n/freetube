import SwiftUI

/// Device-local library following NewPipe's account-free model. Remote channel and playlist
/// destinations remain available when linked from other parts of the app. Its list stays inside
/// the Library tab; RootView owns the navigation stack so pushes do not depend on TabView hosting.
@available(iOS 17.0, *)
struct LibraryScreen: View {
    @State private var localHistoryCount: Int?
    @State private var localSubscriptions = LocalSubscriptionStore.shared
    @State private var localPlaylistCount: Int?
    @State private var rootIsVisible = false
    @State private var didLoadRootData = false
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        List {
            localHistorySection
        }
            .navigationTitle("Library")
            .libraryNavigationTrace("root")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        log.info("Library Settings button tapped")
                        NotificationCenter.default.post(name: .freetubeOpenSettings, object: nil)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
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
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                Task {
                    let count = await PersistenceWriter.shared.watchHistoryCount()
                    guard rootIsVisible else { return }
                    localHistoryCount = count
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
                Task {
                    let count = await localPlaylistCountFromStore()
                    guard rootIsVisible else { return }
                    localPlaylistCount = count
                }
            }
    }

    private func open(_ destination: LibraryNavigationDestination) {
        log.info("Library action requested: \(destination.rawValue)")
        NotificationCenter.default.post(name: .freetubeOpenLibraryDestination, object: destination)
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
            Button("Test Library navigation") {
                open(.probe)
            }
            .foregroundStyle(.secondary)

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
            .libraryNavigationTrace("history row")

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
            .libraryNavigationTrace("subscriptions row")

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
            .libraryNavigationTrace("playlists row")
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
