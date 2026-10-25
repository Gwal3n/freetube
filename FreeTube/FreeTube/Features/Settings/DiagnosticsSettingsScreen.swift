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
                Toggle("Measure player scrolling", isOn: $playerScrollDiagnosticsEnabled)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Measure player scrolling")
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
            } footer: {
                Text("Saving logs creates a new file at launch for troubleshooting. Scroll measurements summarize update gaps after each swipe; they are not video FPS. Enable file logs to share them. Logs omit sensitive URL queries.")
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
        } message: {
            Text("This removes every saved diagnostic log. If \"Save logs to file\" is on, a fresh log file will be opened for new entries.")
        }
    }
}
