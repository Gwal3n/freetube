import SwiftUI

/// A short, native Settings index. Each destination owns one coherent group of controls.
@available(iOS 17.0, *)
struct SettingsScreen: View {
    let onClose: (() -> Void)?
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @State private var model = SettingsViewModel()
    @State private var externalDestination: AppNavigationRequest.Destination?
    @State private var searchText = ""
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        NavigationStack {
            Form {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        settingsLink("Playback", systemImage: "play.circle") {
                            PlaybackSettingsScreen(model: model)
                        }
                        settingsLink("Player", systemImage: "play.rectangle") {
                            PlayerSettingsScreen(model: model)
                        }
                        settingsLink("Captions", systemImage: "captions.bubble") {
                            CaptionsSettingsScreen(model: model)
                        }
                        settingsLink("Downloads", systemImage: "arrow.down.circle") {
                            DownloadsSettingsScreen(model: model)
                        }
                    }

                    Section {
                        settingsLink("Browsing", systemImage: "rectangle.stack") {
                            BrowsingSettingsScreen(model: model)
                        }
                        settingsLink("Appearance", systemImage: "paintbrush") {
                            AppearanceSettingsScreen(model: model)
                        }
                        settingsLink("Library & Data", systemImage: "books.vertical") {
                            LibraryDataSettingsScreen(model: model)
                        }
                        settingsLink("Cache", systemImage: "externaldrive") {
                            CacheSettingsScreen()
                        }
                        settingsLink("Import & Export", systemImage: "square.and.arrow.up.on.square") {
                            ImportDataScreen()
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
                } else {
                    let results = SettingsSearchIndex.results(matching: searchText)
                    if results.isEmpty {
                        ContentUnavailableView(
                            "No Settings Found",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search term.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(results) { result in
                                NavigationLink {
                                    searchDestination(result.destination)
                                        .environment(\.settingsSearchTarget, result.focusTitle)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.displayTitle)
                                            .foregroundStyle(.primary)
                                        if result.destination.section != result.displayTitle {
                                            Text(result.destination.section)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(onClose == nil ? .large : .inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search Settings"
            )
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

    @ViewBuilder
    private func searchDestination(_ destination: SettingsSearchIndex.Destination) -> some View {
        switch destination {
        case .playback: PlaybackSettingsScreen(model: model)
        case .player: PlayerSettingsScreen(model: model)
        case .captions: CaptionsSettingsScreen(model: model)
        case .browsing: BrowsingSettingsScreen(model: model)
        case .appearance: AppearanceSettingsScreen(model: model)
        case .libraryData: LibraryDataSettingsScreen(model: model)
        case .cache: CacheSettingsScreen()
        case .downloads: DownloadsSettingsScreen(model: model)
        case .privacy: PrivacySettingsScreen()
        case .community: CommunityEnhancementsSettingsScreen(model: model)
        case .diagnostics: DiagnosticsSettingsScreen(model: model)
        case .about: AboutSettingsScreen()
        case .playbackSpeeds:
            CustomPlaybackSpeedsScreen(defaultPlaybackRate: Bindable(model).defaultPlaybackRate)
        case .playerControls: PlayerControlsSettingsScreen(model: model)
        case .subscriptionGroups: SubscriptionGroupsScreen(isEmbedded: true)
        case .channelTabs: ChannelTabsSettingsScreen()
        case .tabBar: TabBarSettingsScreen()
        case .importExport: ImportDataScreen()
        case .incognito: IncognitoSettingsScreen()
        case .blockedContent: VideoBlockingSettingsScreen()
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
    }
}
