import SwiftUI

@available(iOS 17.0, *)
struct PlayerSettingsScreen: View {
    let model: SettingsViewModel
    @AppStorage("cacheRecentVideoContent") private var cacheRecentVideoContent = true

    var body: some View {
        Form {
            Section {
                Picker("Double-tap seek", selection: Bindable(model).doubleTapSeekSeconds) {
                    ForEach([5, 10, 15, 30], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .settingsSearchRow("Double-tap seek")
                Picker("Seek preview", selection: Bindable(model).seekPreviewStyle) {
                    Text("Compact").tag(SeekPreviewStyle.compact)
                    Text("Large").tag(SeekPreviewStyle.large)
                    Text("Off").tag(SeekPreviewStyle.off)
                }
                .settingsSearchRow("Seek preview")
                Picker("Vertical swipe in fullscreen", selection: Bindable(model).playerVerticalSwipeAction) {
                    Text("Exit fullscreen").tag(PlayerVerticalSwipeAction.fullscreen)
                    Text("Adjust brightness and volume").tag(PlayerVerticalSwipeAction.adjustPlayback)
                    Text("Off").tag(PlayerVerticalSwipeAction.off)
                }
                .settingsSearchRow("Vertical swipe in fullscreen")
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Picker("Left side", selection: Bindable(model).leftFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .settingsSearchRow("Left side")
                    Picker("Right side", selection: Bindable(model).rightFullscreenSwipeAction) {
                        ForEach(PlayerSwipeAdjustmentAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .settingsSearchRow("Right side")
                }
            } header: {
                Text("Gestures")
            } footer: {
                if model.playerVerticalSwipeAction == .adjustPlayback {
                    Text("Volume swipes adjust FreeTube playback, not the iPhone's system volume.")
                }
            }

            Section {
                Toggle("Remember floating player placement", isOn: Bindable(model).rememberFloatingPlayerPlacement)
                    .tint(.green)
                    .settingsSearchRow("Remember floating player placement")
                Toggle("Show watch progress bars", isOn: Bindable(model).showHistoryProgressBars)
                    .tint(.green)
                    .settingsSearchRow("Show watch progress bars")
                Toggle("Show description", isOn: Bindable(model).showDescription)
                    .tint(.green)
                    .settingsSearchRow("Show description")
                Toggle("Show comments", isOn: Bindable(model).showComments)
                    .tint(.green)
                    .settingsSearchRow("Show comments")
                if model.showComments {
                    Toggle("Show featured comment preview", isOn: Bindable(model).showFeaturedCommentPreview)
                        .tint(.green)
                        .settingsSearchRow("Show featured comment preview")
                }
                Toggle("Show Up Next", isOn: Bindable(model).showUpNext)
                    .tint(.green)
                    .settingsSearchRow("Show Up Next")
                if model.showUpNext {
                    Stepper(value: Bindable(model).upNextInitialCount, in: 3...15) {
                        LabeledContent("Initial Up Next videos") {
                            Text("\(model.upNextInitialCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsSearchRow("Initial Up Next videos")
                }
                Toggle("Prefetch details and comments", isOn: Bindable(model).prefetchVideoDetails)
                    .tint(.green)
                    .disabled(!cacheRecentVideoContent)
                    .settingsSearchRow("Prefetch details and comments")
                NavigationLink {
                    PlayerControlsSettingsScreen(model: model)
                } label: {
                    Label("Customize controls", systemImage: "slider.horizontal.3")
                }
                .tint(.primary)
                .settingsSearchRow("Customize controls")
            } header: {
                Text("Content & controls")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
    }
}
