import SwiftUI

@available(iOS 17.0, *)
struct SponsorBlockSettingsScreen: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable SponsorBlock", isOn: $model.sponsorBlockEnabled)
            } footer: {
                Text("Segment information is fetched in the background and never delays video playback. Skip activity is not reported.")
            }

            Section {
                ForEach(SponsorBlockCategory.allCases) { category in
                    Toggle(category.displayName, isOn: model.binding(for: category))
                }
            } header: {
                Text("Automatically skip")
            } footer: {
                Text("Categories are based on community submissions. Sponsors are enabled by default; all other categories are optional.")
            }
            .disabled(!model.sponsorBlockEnabled)
        }
        .navigationTitle("SponsorBlock")
        .navigationBarTitleDisplayMode(.inline)
    }
}
