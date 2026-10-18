import SwiftUI

/// Keeps Videos as the stable first page while letting users simplify channel profiles.
@available(iOS 17.0, *)
struct ChannelTabsSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @AppStorage("showChannelShortsTab") private var showShorts = true
    @AppStorage("showChannelLiveTab") private var showLive = true
    @AppStorage("showChannelPlaylistsTab") private var showPlaylists = true
    @AppStorage("showChannelAboutTab") private var showAbout = true

    var body: some View {
        Form {
            Section {
                Toggle("Shorts", isOn: $showShorts)
                    .tint(settingsToggleTint)
                Toggle("Live", isOn: $showLive)
                    .tint(settingsToggleTint)
                Toggle("Playlists", isOn: $showPlaylists)
                    .tint(settingsToggleTint)
                Toggle("About", isOn: $showAbout)
                    .tint(settingsToggleTint)
            } footer: {
                Text("The Videos tab is always first. Tabs unavailable on a channel stay hidden regardless of these settings.")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Channel tabs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
