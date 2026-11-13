import SwiftUI

@available(iOS 17.0, *)
struct DiagnosticsSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel
    @State private var logWriter = LogFileWriter.shared
    @AppStorage("playerScrollDiagnosticsEnabled") private var playerScrollDiagnosticsEnabled = false
    @State private var shareLogURL: URL?
    @State private var showingClearLogsConfirmation = false
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "Navigation")

    var body: some View {
        Form {
            Section {
                Toggle("Save logs to file", isOn: Bindable(model).logToFile)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Save logs to file")
                if model.logToFile, let url = logWriter.currentLogFileURL {
                    LabeledContent("Current log") {
                        Text(url.lastPathComponent)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Button {
                    log.info("Settings Share latest log requested")
                    shareLogURL = logWriter.currentLogFileURL ?? LogFileWriter.allLogFiles().first
                } label: {
                    Label("Share latest log…", systemImage: "square.and.arrow.up")
                }
                .disabled(LogFileWriter.allLogFiles().isEmpty)
                .settingsSearchRow("Share latest log…")
                if MacIntegration.isRunningOnMac {
                    Button {
                        MacIntegration.revealInFinder(LogFileWriter.logsDirectory())
                    } label: {
                        Label("Show log folder", systemImage: "folder")
                    }
                    .settingsSearchRow("Show log folder")
                }
                Button(role: .destructive) {
                    showingClearLogsConfirmation = true
                } label: {
                    Label("Clear all logs", systemImage: "trash")
                }
                .disabled(LogFileWriter.allLogFiles().isEmpty)
                .settingsSearchRow("Clear all logs")
            } header: {
                Text("Logs")
            }

            Section {
                Toggle("Log player scroll timing", isOn: $playerScrollDiagnosticsEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Log player scroll timing")
            } header: {
                Text("Player")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { shareLogURL != nil },
            set: { if !$0 { shareLogURL = nil } }
        )) {
            if let url = shareLogURL {
                ActivityShareSheet(activityItems: [url])
            }
        }
        .confirmationDialog(
            "Delete all log files?",
            isPresented: $showingClearLogsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.clearLogFiles()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
