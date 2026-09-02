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
                        ForEach(SponsorBlockBehavior.choices(for: category)) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Show only adds a timeline marker. Ask offers to jump to the video's highlight when one is available.")
            }
            .disabled(!model.sponsorBlockEnabled)
        }
        .navigationTitle("SponsorBlock")
        .navigationBarTitleDisplayMode(.inline)
    }
}
