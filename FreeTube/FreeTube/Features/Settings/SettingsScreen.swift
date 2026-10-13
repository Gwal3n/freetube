import SwiftUI

/// A short, native Settings index. Each destination owns one coherent group of controls.
@available(iOS 17.0, *)
struct SettingsScreen: View {
    let onClose: () -> Void
    @State private var model = SettingsViewModel()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        log.info("Settings Done requested")
                        onClose()
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
