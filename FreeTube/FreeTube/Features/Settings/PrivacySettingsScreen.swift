import SwiftUI

@available(iOS 17.0, *)
struct PrivacySettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true

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
            } footer: {
                Text("Also saves recently visited channels. Turning this off keeps existing entries until you clear them in Search.")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
