import SwiftUI

@available(iOS 17.0, *)
struct CacheSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("cacheRecentVideoContent") private var cacheRecentVideoContent = true
    @AppStorage("prefetchVideoDetails") private var prefetchVideoDetails = true
    @State private var showingClearAllConfirmation = false
    @State private var isClearing = false
    @State private var isMeasuringDiskUsage = true
    @State private var diskUsageBytes: Int64?
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Cache recent video details", isOn: $cacheRecentVideoContent)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Cache recent video details")
                Toggle("Prefetch details and comments", isOn: $prefetchVideoDetails)
                    .tint(settingsToggleTint)
                    .disabled(!cacheRecentVideoContent)
                    .settingsSearchRow("Prefetch details and comments")
            }

            Section {
                LabeledContent("Storage used") {
                    if isMeasuringDiskUsage {
                        ProgressView()
                    } else if let diskUsageBytes {
                        Text(ByteCountFormatter.string(fromByteCount: diskUsageBytes, countStyle: .file))
                            .monospacedDigit()
                    } else {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsSearchRow("Storage used")
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
        .task { await refreshDiskUsage() }
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
                    await refreshDiskUsage()
                    isClearing = false
                    resultMessage = String(localized: "Temporary caches cleared")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func refreshDiskUsage() async {
        isMeasuringDiskUsage = true
        diskUsageBytes = await TemporaryCacheService.diskUsageBytes()
        isMeasuringDiskUsage = false
    }
}
