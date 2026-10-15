import SwiftUI

@available(iOS 17.0, *)
struct LibraryDataSettingsScreen: View {
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
                    .tint(.green)
                    .settingsSearchRow("Save watch history")
                Toggle("Add to history when opened", isOn: Bindable(model).addToHistoryWhenOpened)
                    .tint(.green)
                    .disabled(!model.saveWatchHistory)
                    .settingsSearchRow("Add to history when opened")
                Picker("Keep watch history", selection: Bindable(model).historyRetentionPolicy) {
                    ForEach(HistoryRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(!model.saveWatchHistory)
                .settingsSearchRow("Keep watch history")
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
            } footer: {
                Text("Turning this off stops recording history and playback positions. Existing history stays on this device until you clear it.")
            }

            Section("Library") {
                Toggle("Continue Watching in Library", isOn: Bindable(model).showContinueWatchingMenu)
                    .tint(.green)
                    .settingsSearchRow("Continue Watching in Library")
                Toggle("Library video shelf", isOn: Bindable(model).showLibraryShelf)
                    .tint(.green)
                    .disabled(!model.saveWatchHistory)
                    .settingsSearchRow("Library video shelf")
                if model.showLibraryShelf && model.saveWatchHistory {
                    Picker("Shelf content", selection: Bindable(model).libraryShelfContent) {
                        ForEach(LibraryShelfContent.allCases) { content in
                            Text(content.settingsTitle).tag(content)
                        }
                    }
                    .settingsSearchRow("Shelf content")
                    Stepper(value: Bindable(model).recentLibraryVideoCount, in: 3...12) {
                        LabeledContent("Shelf videos") {
                            Text("\(model.recentLibraryVideoCount)")
                                .monospacedDigit()
                        }
                    }
                    .settingsSearchRow("Shelf videos")
                }
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
        } message: {
            if clearTarget == .progress {
                Text("Saved playback positions and progress bars will be removed. Your watch history will stay on this device.")
            } else {
                Text("This removes watch history stored by FreeTube on this device.")
            }
        }
    }
}
