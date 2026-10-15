import SwiftUI

@available(iOS 17.0, *)
struct BrowsingSettingsScreen: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Show search suggestions", isOn: Bindable(model).showSearchSuggestions)
                    .settingsSearchRow("Show search suggestions")
                Toggle("Save recent searches", isOn: Bindable(model).saveSearchHistory)
                    .settingsSearchRow("Save recent searches")
            } header: {
                Text("Search")
            } footer: {
                Text("Turning off recent searches stops saving new queries. Existing searches remain until cleared from Search.")
            }

            Section {
                Toggle("Large video thumbnails", isOn: Bindable(model).largeSubscriptionFeedThumbnails)
                    .settingsSearchRow("Large video thumbnails")
                Toggle("Mark new uploads", isOn: Bindable(model).showNewSubscriptionUploads)
                    .settingsSearchRow("Mark new uploads")
                Toggle("Refresh feed automatically", isOn: Bindable(model).automaticFeedRefreshEnabled)
                    .settingsSearchRow("Refresh feed automatically")
                if model.automaticFeedRefreshEnabled {
                    Picker("Refresh interval", selection: Bindable(model).automaticFeedRefreshInterval) {
                        ForEach(FeedRefreshInterval.allCases) { interval in
                            switch interval {
                            case .hourly: Text("Every hour").tag(interval)
                            case .everySixHours: Text("Every 6 hours").tag(interval)
                            case .everyTwelveHours: Text("Every 12 hours").tag(interval)
                            case .daily: Text("Every day").tag(interval)
                            }
                        }
                    }
                    .settingsSearchRow("Refresh interval")
                }
            } header: {
                Text("Feed")
            } footer: {
                Text("Automatic refresh runs only while Feed is selected and the app is active. Tab visibility is set in Appearance.")
            }

            Section("Channels") {
                NavigationLink {
                    SubscriptionGroupsScreen(isEmbedded: true)
                } label: {
                    Label("Manage subscription groups", systemImage: "square.stack.3d.up")
                }
                .tint(.primary)
                .settingsSearchRow("Manage subscription groups")
                NavigationLink {
                    ChannelTabsSettingsScreen()
                } label: {
                    Label("Channel tabs", systemImage: "rectangle.stack")
                }
                .tint(.primary)
                .settingsSearchRow("Channel tabs")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Browsing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
