import SwiftUI

/// Controls the bounded in-memory recent-video cache and explicit disposable-cache removal.
@available(iOS 17.0, *)
struct CacheSettingsScreen: View {
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("cacheRecentVideoContent") private var cacheRecentVideoContent = true
    @State private var showingClearAllConfirmation = false
    @State private var isClearing = false
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Cache recent video details", isOn: $cacheRecentVideoContent)
                    .settingsSearchRow("Cache recent video details")
            } footer: {
                Text("Keeps details and the first comments page for up to 12 recently opened videos in memory. Nothing is saved to disk. Turning this off also stops detail prefetching.")
            }

            Section {
                Button("Clear recent video cache") {
                    TemporaryCacheService.clearRecentVideoContent()
                    resultMessage = String(localized: "Recent video cache cleared")
                }
                .settingsSearchRow("Clear recent video cache")

                Button("Clear all temporary caches", role: .destructive) {
                    showingClearAllConfirmation = true
                }
                .disabled(isClearing)
                .settingsSearchRow("Clear all temporary caches")
            } footer: {
                Text("Clears thumbnails, recent video details, and short-lived stream and community results. Downloads, playlists, subscriptions, and history remain intact. Images may reload afterward.")
            }

            if isClearing {
                Section { ProgressView("Clearing caches…") }
            } else if let resultMessage {
                Section { Text(resultMessage).foregroundStyle(.secondary) }
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Cache")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: cacheRecentVideoContent) { _, enabled in
            if !enabled { TemporaryCacheService.clearRecentVideoContent() }
        }
        .confirmationDialog(
            "Clear all temporary caches?",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Caches", role: .destructive) {
                isClearing = true
                Task {
                    await TemporaryCacheService.clearAll(player: player)
                    isClearing = false
                    resultMessage = String(localized: "Temporary caches cleared")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloads and personal data will not be removed.")
        }
    }
}
