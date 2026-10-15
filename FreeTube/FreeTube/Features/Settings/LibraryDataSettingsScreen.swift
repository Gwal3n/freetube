import SwiftUI

@available(iOS 17.0, *)
struct LibraryDataSettingsScreen: View {
    let model: SettingsViewModel
    @State private var showingClearHistoryConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Save watch history", isOn: Bindable(model).saveWatchHistory)
                    .settingsSearchRow("Save watch history")
                Toggle("Add to history when opened", isOn: Bindable(model).addToHistoryWhenOpened)
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
                    showingClearHistoryConfirmation = true
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
                    .settingsSearchRow("Continue Watching in Library")
                Toggle("Library video shelf", isOn: Bindable(model).showLibraryShelf)
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
            "Clear local watch history?",
            isPresented: $showingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                model.clearLocalHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes watch history stored by FreeTube on this device.")
        }
    }
}
