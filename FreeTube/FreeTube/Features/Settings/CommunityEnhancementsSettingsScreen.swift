import SwiftUI

@available(iOS 17.0, *)
struct CommunityEnhancementsSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    @Bindable var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("SponsorBlock", isOn: $model.sponsorBlockEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("SponsorBlock")
            } header: {
                Text("SponsorBlock")
            }

            Section {
                ForEach(SponsorBlockCategory.allCases) { category in
                    Picker(category.displayName, selection: model.sponsorBlockBehaviorBinding(for: category)) {
                        ForEach(SponsorBlockBehavior.choices(for: category)) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .settingsSearchRow(localizedTitle: category.displayName)
                }
            } header: {
                Text("Categories")
                    .settingsSearchRow("Categories")
            }
            .disabled(!model.sponsorBlockEnabled)

            Section {
                NavigationLink {
                    SponsorBlockColorsSettingsScreen(model: model)
                } label: {
                    Label("Segment colors", systemImage: "paintpalette")
                }
                .settingsSearchRow("Segment colors")
            }
            .disabled(!model.sponsorBlockEnabled)

            Section("Skipping") {
                Stepper(value: $model.sponsorBlockMinimumSkipSeconds, in: 0...30, step: 1) {
                    LabeledContent("Minimum length to auto-skip") {
                        if model.sponsorBlockMinimumSkipSeconds == 0 {
                            Text("Any length")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(model.sponsorBlockMinimumSkipSeconds)) seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .settingsSearchRow("Minimum length to auto-skip")
                Stepper(value: $model.sponsorBlockNoticeSeconds, in: 1...15, step: 1) {
                    LabeledContent("Undo banner duration") {
                        Text("\(Int(model.sponsorBlockNoticeSeconds)) seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsSearchRow("Undo banner duration")
            }
            .disabled(!model.sponsorBlockEnabled)

            Section {
                Toggle("Replace titles", isOn: $model.deArrowTitles)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Replace titles")
                Toggle("Replace thumbnails", isOn: $model.deArrowThumbnails)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Replace thumbnails")
                if model.deArrowThumbnails {
                    Toggle("Random frame if none submitted", isOn: $model.deArrowRandomThumbnails)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Random frame if none submitted")
                }
            } header: {
                Text(verbatim: "DeArrow")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("SponsorBlock & DeArrow")
        .navigationBarTitleDisplayMode(.inline)
    }
}
