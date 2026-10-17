import SwiftUI

@available(iOS 17.0, *)
struct BrowsingSettingsScreen: View {
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Show search suggestions", isOn: Bindable(model).showSearchSuggestions)
                    .tint(.green)
                    .settingsSearchRow("Show search suggestions")
                Toggle("Save recent searches", isOn: Bindable(model).saveSearchHistory)
                    .tint(.green)
                    .settingsSearchRow("Save recent searches")
            } header: {
                Text("Search")
            } footer: {
                Text("Turning off recent searches stops saving new queries. Existing searches remain until cleared from Search.")
            }

            Section {
                Toggle("Large video thumbnails", isOn: Bindable(model).largeSubscriptionFeedThumbnails)
                    .tint(.green)
                    .settingsSearchRow("Large video thumbnails")
                Toggle("Show channel avatars", isOn: Bindable(model).showFeedChannelAvatars)
                    .tint(.green)
                    .settingsSearchRow("Show channel avatars")
                Toggle("Mark new uploads", isOn: Bindable(model).showNewSubscriptionUploads)
                    .tint(.green)
                    .settingsSearchRow("Mark new uploads")
                Toggle("Space out related uploads", isOn: Bindable(model).spaceSubscriptionFeedVideos)
                    .tint(.green)
                    .settingsSearchRow("Space out related uploads")
                if model.spaceSubscriptionFeedVideos {
                    Stepper(value: Bindable(model).feedChannelSpacing, in: 0...5) {
                        LabeledContent("Same channel gap") {
                            if model.feedChannelSpacing == 0 {
                                Text("Off").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: "\(model.feedChannelSpacing)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .settingsSearchRow("Same channel gap")
                    Stepper(value: Bindable(model).feedGroupSpacing, in: 0...5) {
                        LabeledContent("Same group gap") {
                            if model.feedGroupSpacing == 0 {
                                Text("Off").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: "\(model.feedGroupSpacing)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .settingsSearchRow("Same group gap")
                    Picker("Maximum date shift", selection: Bindable(model).feedSpacingMaximumShiftHours) {
                        Text("6 hours").tag(6)
                        Text("24 hours").tag(24)
                        Text("3 days").tag(72)
                    }
                    .settingsSearchRow("Maximum date shift")
                }
                Toggle("Refresh feed automatically", isOn: Bindable(model).automaticFeedRefreshEnabled)
                    .tint(.green)
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
                Toggle("Update feed view counts", isOn: Bindable(model).automaticFeedViewCountsEnabled)
                    .tint(.green)
                    .settingsSearchRow("Update feed view counts")
                if model.automaticFeedViewCountsEnabled {
                    Picker("View count batch interval", selection: Bindable(model).automaticFeedViewCountInterval) {
                        ForEach(FeedRefreshInterval.allCases) { interval in
                            switch interval {
                            case .hourly: Text("Every hour").tag(interval)
                            case .everySixHours: Text("Every 6 hours").tag(interval)
                            case .everyTwelveHours: Text("Every 12 hours").tag(interval)
                            case .daily: Text("Every day").tag(interval)
                            }
                        }
                    }
                    .settingsSearchRow("View count batch interval")
                }
            } header: {
                Text("Feed")
            } footer: {
                Text("Spacing puts the selected number of videos between related uploads when possible. It only moves uploads within the chosen time range. Automatic updates run only while Feed is selected and the app is active. View counts update four channels per interval without reloading the feed.")
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
