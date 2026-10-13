import SwiftUI

@available(iOS 17.0, *)
struct LibraryDataSettingsScreen: View {
    let model: SettingsViewModel
    @State private var showingClearHistoryConfirmation = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ImportDataScreen()
                } label: {
                    Label("Import & Export", systemImage: "square.and.arrow.down")
                }
                .tint(.primary)
            }

            Section {
                Toggle("Save watch history", isOn: Bindable(model).saveWatchHistory)
                Toggle("Add to history when opened", isOn: Bindable(model).addToHistoryWhenOpened)
                    .disabled(!model.saveWatchHistory)
                Picker("Keep watch history", selection: Bindable(model).historyRetentionPolicy) {
                    ForEach(HistoryRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(!model.saveWatchHistory)
                Button(role: .destructive) {
                    showingClearHistoryConfirmation = true
                } label: {
                    Label("Clear Watch History", systemImage: "trash")
                }
            } header: {
                Text("Watch history")
            } footer: {
                Text("Turning this off stops recording history and playback positions. Existing history stays on this device until you clear it.")
            }

            Section("Library") {
                Toggle("Continue Watching in Library", isOn: Bindable(model).showContinueWatchingMenu)
                Toggle("Library video shelf", isOn: Bindable(model).showLibraryShelf)
                    .disabled(!model.saveWatchHistory)
                if model.showLibraryShelf && model.saveWatchHistory {
                    Picker("Shelf content", selection: Bindable(model).libraryShelfContent) {
                        ForEach(LibraryShelfContent.allCases) { content in
                            Text(content.settingsTitle).tag(content)
                        }
                    }
                    Stepper(value: Bindable(model).recentLibraryVideoCount, in: 3...12) {
                        LabeledContent("Shelf videos") {
                            Text("\(model.recentLibraryVideoCount)")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
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
