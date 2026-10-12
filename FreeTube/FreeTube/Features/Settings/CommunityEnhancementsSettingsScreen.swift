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
                Text("Show only marks skip segments on the timeline. Community chapters appear in the chapter list, and full-video labels mark the whole timeline. Ask offers to jump to a highlight.")
            }
            .disabled(!model.sponsorBlockEnabled)

            Section("Skipping") {
                Stepper(value: $model.sponsorBlockMinimumSkipSeconds, in: 0...30, step: 1) {
                    LabeledContent("Minimum segment length") {
                        if model.sponsorBlockMinimumSkipSeconds == 0 {
                            Text("Any length")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(model.sponsorBlockMinimumSkipSeconds)) seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Stepper(value: $model.sponsorBlockNoticeSeconds, in: 1...15, step: 1) {
                    LabeledContent("Skip notice duration") {
                        Text("\(Int(model.sponsorBlockNoticeSeconds)) seconds")
                            .foregroundStyle(.secondary)
                    }
                }
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
