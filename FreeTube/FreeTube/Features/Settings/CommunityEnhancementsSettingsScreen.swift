import SwiftUI

/// Native settings for the two optional, anonymous community enhancements.
@available(iOS 17.0, *)
struct CommunityEnhancementsSettingsScreen: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable SponsorBlock", isOn: $model.sponsorBlockEnabled)
            } header: {
                Text("SponsorBlock")
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

            Section {
                Toggle("Replace video titles", isOn: $model.deArrowTitles)
                Toggle("Replace video thumbnails", isOn: $model.deArrowThumbnails)
                if model.deArrowThumbnails {
                    Toggle("Random thumbnail when no submission exists", isOn: $model.deArrowRandomThumbnails)
                }
            } header: {
                Text(verbatim: "DeArrow")
            } footer: {
                Text("Use community titles and video frames to reduce clickbait. If no thumbnail has been submitted, a stable random frame can be requested instead. Tap the small switch on a video to see its original title and thumbnail. Originals stay saved on this device. Enabling this sends anonymous requests to DeArrow; thumbnail requests include the video ID. If the service is unavailable, the originals remain visible.")
            }
        }
        .navigationTitle("Community enhancements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
