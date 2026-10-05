import SwiftUI

/// Keeps Videos as the stable first page while letting users simplify channel profiles.
@available(iOS 17.0, *)
struct ChannelTabsSettingsScreen: View {
    @AppStorage("showChannelShortsTab") private var showShorts = true
    @AppStorage("showChannelLiveTab") private var showLive = true
    @AppStorage("showChannelPlaylistsTab") private var showPlaylists = true
    @AppStorage("showChannelAboutTab") private var showAbout = true

    var body: some View {
        Form {
            Section {
                Toggle("Shorts", isOn: $showShorts)
                Toggle("Live", isOn: $showLive)
                Toggle("Playlists", isOn: $showPlaylists)
                Toggle("About", isOn: $showAbout)
            } footer: {
                Text("The Videos tab is always first. Tabs unavailable on a channel stay hidden regardless of these settings.")
            }
        }
        .navigationTitle("Channel tabs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
