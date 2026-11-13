import SwiftUI

@available(iOS 17.0, *)
struct LibraryDataSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    private enum ClearTarget: Equatable {
        case progress, history
    }

    let model: SettingsViewModel
    @State private var clearTarget: ClearTarget?

    private var clearConfirmationTitle: LocalizedStringKey {
        if clearTarget == .progress {
            return "Clear saved watch progress?"
        }
        return "Clear local watch history?"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Save watch history", isOn: Bindable(model).saveWatchHistory)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Save watch history")
                Toggle("Add when a video opens", isOn: Bindable(model).addToHistoryWhenOpened)
                    .tint(settingsToggleTint)
                    .disabled(!model.saveWatchHistory)
                    .settingsSearchRow("Add when a video opens")
                Picker("Keep history for", selection: Bindable(model).historyRetentionPolicy) {
                    ForEach(HistoryRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(!model.saveWatchHistory)
                .settingsSearchRow("Keep history for")
                Button(role: .destructive) {
                    clearTarget = .progress
                } label: {
                    Label("Clear Watch Progress", systemImage: "gobackward")
                }
                .settingsSearchRow("Clear Watch Progress")
                Button(role: .destructive) {
                    clearTarget = .history
                } label: {
                    Label("Clear Watch History", systemImage: "trash")
                }
                .settingsSearchRow("Clear Watch History")
            } header: {
                Text("Watch history")
            }

            Section {
                Toggle("Show Continue Watching", isOn: Bindable(model).showContinueWatchingMenu)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Show Continue Watching")
                Toggle("Show video shelf", isOn: Bindable(model).showLibraryShelf)
                    .tint(settingsToggleTint)
                    .disabled(!model.saveWatchHistory)
                    .settingsSearchRow("Show video shelf")
                if model.showLibraryShelf && model.saveWatchHistory {
                    Picker("Shelf content", selection: Bindable(model).libraryShelfContent) {
                        ForEach(LibraryShelfContent.allCases) { content in
                            Text(content.settingsTitle).tag(content)
                        }
                    }
                    .settingsSearchRow("Shelf content")
                    Stepper(value: Bindable(model).recentLibraryVideoCount, in: 3...12) {
                        LabeledContent("Videos on shelf") {
                            Text("\(model.recentLibraryVideoCount)")
                                .monospacedDigit()
                        }
                    }
                    .settingsSearchRow("Videos on shelf")
                }
            } header: {
                Text("Library")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Library & Data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            clearConfirmationTitle,
            isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if clearTarget == .progress {
                Button("Clear Progress", role: .destructive) {
                    model.clearWatchProgress()
                }
            } else if clearTarget == .history {
                Button("Clear History", role: .destructive) {
                    model.clearLocalHistory()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
