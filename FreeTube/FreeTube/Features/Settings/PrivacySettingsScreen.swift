import SwiftUI

@available(iOS 17.0, *)
struct PrivacySettingsScreen: View {
    @AppStorage("incognitoEnabled") private var incognitoEnabled = false

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
                .tint(.primary)
                .settingsSearchRow("Incognito")
                NavigationLink {
                    VideoBlockingSettingsScreen()
                } label: {
                    Label("Blocked content", systemImage: "hand.raised")
                }
                .tint(.primary)
                .settingsSearchRow("Blocked content")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
