import SwiftUI

/// A short, native Settings index. Each destination owns one coherent group of controls.
@available(iOS 17.0, *)
struct SettingsScreen: View {
    let onClose: (() -> Void)?
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var model = SettingsViewModel()
    @State private var externalDestination: AppNavigationRequest.Destination?
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    settingsLink("Playback", systemImage: "play.circle") {
                        PlaybackSettingsScreen(model: model)
                    }
                    settingsLink("Browsing", systemImage: "rectangle.stack") {
                        BrowsingSettingsScreen(model: model)
                    }
                    settingsLink("Appearance", systemImage: "paintbrush") {
                        AppearanceSettingsScreen(model: model)
                    }
                    settingsLink("Library & Data", systemImage: "books.vertical") {
                        LibraryDataSettingsScreen(model: model)
                    }
                    settingsLink("Downloads", systemImage: "arrow.down.circle") {
                        DownloadsSettingsScreen(model: model)
                    }
                }

                Section {
                    settingsLink("Privacy", systemImage: "hand.raised") {
                        PrivacySettingsScreen()
                    }
                    settingsLink("SponsorBlock & DeArrow", systemImage: "sparkles") {
                        CommunityEnhancementsSettingsScreen(model: model)
                    }
                }

                Section {
                    settingsLink("Diagnostics", systemImage: "stethoscope") {
                        DiagnosticsSettingsScreen(model: model)
                    }
                    settingsLink("About", systemImage: "info.circle") {
                        AboutSettingsScreen()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(onClose == nil ? .large : .inline)
            .navigationDestination(item: $externalDestination) { destination in
                switch destination {
                case .channel(let id): ChannelScreen(channelID: id)
                case .playlist(let id): PlaylistScreen(playlistID: id)
                case .localPlaylist(let id): LocalPlaylistScreen(playlistID: id)
                }
            }
            .onChange(of: navigationRouter.settings?.id, initial: true) { _, _ in
                guard let request = navigationRouter.settings else { return }
                navigationRouter.settings = nil
                externalDestination = request.destination
            }
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            log.info("Settings Done requested")
                            onClose()
                        }
                    }
                }
            }
        }
    }

    private func settingsLink<Destination: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
        }
        .tint(.primary)
    }
}
