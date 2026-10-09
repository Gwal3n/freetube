import SwiftUI

/// Configures local-only privacy behavior. Existing saved data is never deleted by this mode.
@available(iOS 17.0, *)
struct IncognitoSettingsScreen: View {
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
            } footer: {
                Text("Incognito changes only future activity while it is on. It does not delete existing data or hide network activity from YouTube or your internet provider.")
            }

            Section("While Incognito Is On") {
                Toggle("Don't save searches", isOn: $skipSearchHistory)
                Toggle("Don't save watch history", isOn: $skipWatchHistory)
                Toggle("Don't save watch progress", isOn: $skipWatchProgress)
                Toggle("Hide watch progress", isOn: $hideWatchProgress)
            }

            Section {
                Toggle("Hide Feed tab", isOn: $hideFeed)
                Toggle("Hide Library tab", isOn: $hideLibrary)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Downloads and Search remain available. If Library is hidden, Settings can be opened from Search.")
            }
        }
        .navigationTitle("Incognito")
        .navigationBarTitleDisplayMode(.inline)
    }
}
