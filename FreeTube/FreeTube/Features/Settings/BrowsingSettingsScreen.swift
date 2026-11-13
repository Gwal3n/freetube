import SwiftUI

@available(iOS 17.0, *)
struct BrowsingSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @AppStorage("autoLoadMoreSearchItems") private var autoLoadMoreSearchItems = true
    @AppStorage("autoLoadMoreFeedItems") private var autoLoadMoreFeedItems = true
    @AppStorage("openFeedChannelsOnTap") private var openFeedChannelsOnTap = false
    @AppStorage("showFeedFilterButton") private var showFeedFilterButton = true
    @AppStorage("feedSuggestionsEnabled") private var feedSuggestionsEnabled = false
    @AppStorage("feedSuggestionDensity") private var feedSuggestionDensity = 10
    @AppStorage("watchProgressColorMode") private var watchProgressColorMode = WatchIndicatorStyle.ColorMode.red.rawValue
    @AppStorage("watchProgressCustomHex") private var watchProgressCustomHex = "#FF0000"
    @AppStorage("finishedVideoIndicator") private var finishedVideoIndicator = WatchIndicatorStyle.FinishedMode.none.rawValue
    let model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Show search suggestions", isOn: Bindable(model).showSearchSuggestions)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show search suggestions")
                Toggle("Load more as you scroll", isOn: $autoLoadMoreSearchItems)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Load more as you scroll")
            } header: {
                Text("Search")
            }

            Section {
                Toggle("Large thumbnails", isOn: Bindable(model).largeSubscriptionFeedThumbnails)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Large thumbnails")
                Toggle("Show channel avatars", isOn: Bindable(model).showFeedChannelAvatars)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show channel avatars")
                Toggle("Show watch progress", isOn: Bindable(model).showHistoryProgressBars)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show watch progress")
                if model.showHistoryProgressBars {
                    Picker("Progress color", selection: $watchProgressColorMode) {
                        Text("Red").tag(WatchIndicatorStyle.ColorMode.red.rawValue)
                        Text("Accent color").tag(WatchIndicatorStyle.ColorMode.accent.rawValue)
                        Text("Custom").tag(WatchIndicatorStyle.ColorMode.custom.rawValue)
                    }
                    .settingsSearchRow("Progress color")
                    if watchProgressColorMode == WatchIndicatorStyle.ColorMode.custom.rawValue {
                        ColorPicker("Custom progress color", selection: Binding(
                            get: { WatchIndicatorStyle.color(hex: watchProgressCustomHex) ?? .red },
                            set: { watchProgressCustomHex = WatchIndicatorStyle.hex(color: $0) }
                        ), supportsOpacity: false)
                        .settingsSearchRow("Custom progress color")
                    }
                    Picker("Finished videos", selection: $finishedVideoIndicator) {
                        Text("Full progress bar").tag(WatchIndicatorStyle.FinishedMode.fullBar.rawValue)
                        Text("Checkmark").tag(WatchIndicatorStyle.FinishedMode.checkmark.rawValue)
                        Text("No indicator").tag(WatchIndicatorStyle.FinishedMode.none.rawValue)
                    }
                    .settingsSearchRow("Finished videos")
                }
            } header: {
                Text("Lists")
            }

            Section {
                Toggle("Tap channel to open", isOn: $openFeedChannelsOnTap)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Tap channel to open")
                Toggle("Show filter button", isOn: $showFeedFilterButton)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show filter button")
                Toggle("Load more videos as you scroll", isOn: $autoLoadMoreFeedItems)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Load more videos as you scroll")
                Toggle("Include suggested videos", isOn: $feedSuggestionsEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Include suggested videos")
                if feedSuggestionsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Suggestion density") {
                            Text(verbatim: "\(feedSuggestionDensity)%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(feedSuggestionDensity) },
                            set: { feedSuggestionDensity = Int($0) }
                        ), in: 0...50, step: 5)
                        .tint(settingsToggleTint)
                    }
                    .settingsSearchRow("Suggestion density")
                }
                Toggle("Mark new uploads", isOn: Bindable(model).showNewSubscriptionUploads)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Mark new uploads")
                Toggle("Space out related videos", isOn: Bindable(model).spaceSubscriptionFeedVideos)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Space out related videos")
                if model.spaceSubscriptionFeedVideos {
                    Stepper(value: Bindable(model).feedChannelSpacing, in: 0...5) {
                        LabeledContent("Gap for same channel") {
                            if model.feedChannelSpacing == 0 {
                                Text("Off").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: "\(model.feedChannelSpacing)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .settingsSearchRow("Gap for same channel")
                    Stepper(value: Bindable(model).feedGroupSpacing, in: 0...5) {
                        LabeledContent("Gap for same group") {
                            if model.feedGroupSpacing == 0 {
                                Text("Off").foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: "\(model.feedGroupSpacing)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .settingsSearchRow("Gap for same group")
                    Picker("Max time window", selection: Bindable(model).feedSpacingMaximumShiftHours) {
                        Text("6 hours").tag(6)
                        Text("24 hours").tag(24)
                        Text("3 days").tag(72)
                    }
                    .settingsSearchRow("Max time window")
                }
            } header: {
                Text("Feed")
            }

            Section {
                Toggle("Refresh automatically", isOn: Bindable(model).automaticFeedRefreshEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Refresh automatically")
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
                Toggle("Refresh view counts", isOn: Bindable(model).automaticFeedViewCountsEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Refresh view counts")
                if model.automaticFeedViewCountsEnabled {
                    Picker("View count interval", selection: Bindable(model).automaticFeedViewCountInterval) {
                        ForEach(FeedRefreshInterval.allCases) { interval in
                            switch interval {
                            case .hourly: Text("Every hour").tag(interval)
                            case .everySixHours: Text("Every 6 hours").tag(interval)
                            case .everyTwelveHours: Text("Every 12 hours").tag(interval)
                            case .daily: Text("Every day").tag(interval)
                            }
                        }
                    }
                    .settingsSearchRow("View count interval")
                }
            } header: {
                Text("Automatic updates")
            }

            Section("Channels") {
                NavigationLink {
                    SubscriptionGroupsScreen(isEmbedded: true)
                } label: {
                    Label("Subscription groups", systemImage: "square.stack.3d.up")
                }
                .settingsSearchRow("Subscription groups")
                NavigationLink {
                    ChannelTabsSettingsScreen()
                } label: {
                    Label("Channel tabs", systemImage: "rectangle.stack")
                }
                .settingsSearchRow("Channel tabs")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Browsing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
