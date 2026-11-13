import SwiftUI

/// Configures local-only privacy behavior. Existing saved data is never deleted by this mode.
@available(iOS 17.0, *)
struct IncognitoSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @AppStorage("incognitoEnabled") private var enabled = false
    @AppStorage("incognitoSkipSearchHistory") private var skipSearchHistory = true
    @AppStorage("incognitoSkipWatchHistory") private var skipWatchHistory = true
    @AppStorage("incognitoSkipWatchProgress") private var skipWatchProgress = true
    @AppStorage("incognitoHideWatchProgress") private var hideWatchProgress = true
    @AppStorage("incognitoHideFeed") private var hideFeed = false
    @AppStorage("incognitoHideLibrary") private var hideLibrary = false

    var body: some View {
        Form {
            Section {
                Toggle("Incognito", isOn: $enabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Incognito")
            }

            Section("While on") {
                Toggle("Don't save searches", isOn: $skipSearchHistory)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Don't save searches")
                Toggle("Don't save watch history", isOn: $skipWatchHistory)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Don't save watch history")
                Toggle("Don't save watch progress", isOn: $skipWatchProgress)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Don't save watch progress")
                Toggle("Hide watch progress bars", isOn: $hideWatchProgress)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Hide watch progress bars")
            }

            Section {
                Toggle("Hide Feed tab", isOn: $hideFeed)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Hide Feed tab")
                Toggle("Hide Library tab", isOn: $hideLibrary)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Hide Library tab")
            } header: {
                Text("Tabs")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Incognito")
        .navigationBarTitleDisplayMode(.inline)
    }
}
