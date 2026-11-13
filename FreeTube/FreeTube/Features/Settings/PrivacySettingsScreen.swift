import SwiftUI

@available(iOS 17.0, *)
struct PrivacySettingsScreen: View {
    private enum EditedLimit {
        case searches, channels
    }

    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true
    @AppStorage("saveRecentChannels") private var saveRecentChannels = true
    @AppStorage(RecentHistoryLimits.searchKey) private var recentSearchLimit = RecentHistoryLimits.defaultSearchLimit
    @AppStorage(RecentHistoryLimits.channelKey) private var recentChannelLimit = RecentHistoryLimits.defaultChannelLimit
    @State private var editedLimit: EditedLimit?
    @State private var limitText = ""

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    IncognitoSettingsScreen()
                } label: {
                    HStack {
                        Label("Incognito", systemImage: "eye.slash")
                        Spacer()
                        if incognitoEnabled {
                            Text("On")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .settingsSearchRow("Incognito")
                NavigationLink {
                    VideoBlockingSettingsScreen()
                } label: {
                    Label("Blocked content", systemImage: "hand.raised")
                }
                .settingsSearchRow("Blocked content")
            }

            Section {
                Toggle("Save recent searches", isOn: $saveSearchHistory)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Save recent searches")
                limitRow("Searches to keep", value: recentSearchLimit, limit: .searches)
                    .disabled(!saveSearchHistory)
                    .settingsSearchRow("Searches to keep")
                Toggle("Save recent channels", isOn: $saveRecentChannels)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Save recent channels")
                limitRow("Channels to keep", value: recentChannelLimit, limit: .channels)
                    .disabled(!saveRecentChannels)
                    .settingsSearchRow("Channels to keep")
            } header: {
                Text("Recent history")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            editedLimit == .channels
                ? LocalizedStringKey("Channels to keep")
                : LocalizedStringKey("Searches to keep"),
            isPresented: Binding(
                get: { editedLimit != nil },
                set: { if !$0 { editedLimit = nil } }
            )
        ) {
            TextField("Number", text: $limitText)
                .keyboardType(.numberPad)
            Button("Save") { saveLimit() }
                .disabled(parsedLimit == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a number from 1 to 500.")
        }
    }

    private func limitRow(_ title: LocalizedStringKey, value: Int, limit: EditedLimit) -> some View {
        Button {
            limitText = String(value)
            editedLimit = limit
        } label: {
            LabeledContent(title) {
                Text(verbatim: "\(value)")
            }
        }
        .tint(.primary)
    }

    private var parsedLimit: Int? {
        guard let value = Int(limitText.trimmingCharacters(in: .whitespaces)),
              RecentHistoryLimits.range.contains(value) else { return nil }
        return value
    }

    private func saveLimit() {
        guard let value = parsedLimit else { return }
        switch editedLimit {
        case .searches: recentSearchLimit = value
        case .channels: recentChannelLimit = value
        case nil: break
        }
    }
}
