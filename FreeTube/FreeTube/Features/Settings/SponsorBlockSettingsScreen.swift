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
                    Picker(category.displayName, selection: model.sponsorBlockBehaviorBinding(for: category)) {
                        ForEach(SponsorBlockBehavior.allCases) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Show only adds a timeline marker without skipping. Highlights shown on the timeline ask before skipping when reached.")
            }
            .disabled(!model.sponsorBlockEnabled)
        }
        .navigationTitle("SponsorBlock")
        .navigationBarTitleDisplayMode(.inline)
    }
}
