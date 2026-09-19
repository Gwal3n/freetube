import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct ImportDataScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ImportKind: Equatable {
        case backup
        case subscriptions
        case playlists

        var contentTypes: [UTType] {
            switch self {
            case .backup: [.json]
            case .subscriptions, .playlists: [.commaSeparatedText, .plainText]
            }
        }

        var allowsMultipleSelection: Bool { self == .playlists }
    }

    private enum DataOperation {
        case exporting
        case restoring
        case importingSubscriptions
        case importingPlaylists(completed: Int, total: Int)

        var title: String {
            switch self {
            case .exporting: "Preparing Backup"
            case .restoring: "Restoring Backup"
            case .importingSubscriptions: "Importing Subscriptions"
            case .importingPlaylists: "Importing Playlists"
            }
        }

        var detail: String {
            switch self {
            case .exporting:
                "Collecting your settings and local data…"
            case .restoring:
                "Replacing local data from your backup…"
            case .importingSubscriptions:
                "Adding channels to Local Subscriptions…"
            case .importingPlaylists(let completed, let total):
                "Importing playlist \(min(completed + 1, total)) of \(total)…"
            }
        }

        var progress: Double? {
            guard case .importingPlaylists(let completed, let total) = self, total > 0 else {
                return nil
            }
            return Double(completed) / Double(total)
        }
    }

    @State private var importKind: ImportKind = .backup
    @State private var showingImporter = false
    @State private var showingBackupExporter = false
    @State private var confirmsBackupRestore = false
    @State private var pendingBackup: AppBackup?
    @State private var exportDocument = AppBackupDocument(data: Data())
    @State private var activeOperation: DataOperation?
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    private let playlistService = LocalPlaylistService()

    private var isWorking: Bool { activeOperation != nil }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await exportAllData() }
                } label: {
                    Label("Export All Settings and Data", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking)
                Button {
                    presentImporter(.backup)
                } label: {
                    Label("Import Full Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
            } header: {
                Text("Full Backup")
            } footer: {
                Text("Includes settings, subscriptions, playlists with resolved video information, watch and search history, and saved items. Account credentials, downloads, logs, and temporary caches are excluded.")
            }

            Section {
                Button {
                    presentImporter(.subscriptions)
                } label: {
                    Label("Import Subscriptions CSV", systemImage: "person.2.badge.plus")
                }
                .disabled(isWorking)
                Button {
                    presentImporter(.playlists)
                } label: {
                    Label("Import Playlist CSV Files", systemImage: "music.note.list")
                }
                .disabled(isWorking)
            } footer: {
                Text("Imports stay on this device. Each playlist CSV becomes a separate personal playlist.")
            }

            if let activeOperation {
                Section(activeOperation.title) {
                    HStack(spacing: 12) {
                        if let progress = activeOperation.progress {
                            ProgressView(value: progress)
                                .frame(width: 44)
                        } else {
                            ProgressView()
                        }
                        Text(activeOperation.detail)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isWorking)
        .navigationTitle("Import Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importKind.contentTypes,
            allowsMultipleSelection: importKind.allowsMultipleSelection
        ) { result in
            handleImport(result, kind: importKind)
        }
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "FreeTube Backup"
        ) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("Import Complete", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(resultMessage ?? "") }
        .alert("Couldn’t Import Data", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: $confirmsBackupRestore,
            titleVisibility: .visible
        ) {
            Button("Replace Local Data", role: .destructive) {
                Task { await restorePendingBackup() }
            }
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("Current settings, subscriptions, playlists, history, and saved items will be replaced by the backup.")
        }
    }

    private func presentImporter(_ kind: ImportKind) {
        guard !isWorking, !showingImporter else { return }
        importKind = kind
        showingImporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>, kind: ImportKind) {
        switch kind {
        case .backup:
            prepareBackupImport(result)
        case .subscriptions:
            importSubscriptions(result)
        case .playlists:
            Task { await importPlaylists(result) }
        }
    }

    private func exportAllData() async {
        guard !isWorking else { return }
        activeOperation = .exporting
        defer { activeOperation = nil }
        do {
            let backup = try await AppBackupService.shared.makeBackup()
            exportDocument = AppBackupDocument(data: try AppBackupService.shared.encode(backup))
            showingBackupExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareBackupImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let backup = try AppBackupService.shared.decode(Data(contentsOf: url))
            pendingBackup = backup
            // The document picker is still completing its dismissal during this callback.
            // Presenting a confirmation dialog in the same update can be dropped by SwiftUI.
            Task { @MainActor in
                await Task.yield()
                guard pendingBackup != nil else { return }
                confirmsBackupRestore = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePendingBackup() async {
        guard let backup = pendingBackup, !isWorking else { return }
        activeOperation = .restoring
        defer {
            activeOperation = nil
            pendingBackup = nil
        }
        do {
            try await AppBackupService.shared.restore(backup)
            resultMessage = "Backup restored. Reopen the app to apply every restored setting."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importSubscriptions(_ result: Result<[URL], Error>) {
        guard !isWorking else { return }
        activeOperation = .importingSubscriptions
        defer { activeOperation = nil }
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let count = try LocalSubscriptionStore.shared.importCSV(data: Data(contentsOf: url))
            resultMessage = "Imported \(count) \(count == 1 ? "channel" : "channels")."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPlaylists(_ result: Result<[URL], Error>) async {
        guard !isWorking else { return }
        defer { activeOperation = nil }
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            activeOperation = .importingPlaylists(completed: 0, total: urls.count)
            var imported = 0
            var skipped = [String]()
            for (index, url) in urls.enumerated() {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    _ = try await playlistService.importCSV(
                        data: Data(contentsOf: url),
                        filename: url.lastPathComponent
                    )
                    imported += 1
                } catch {
                    skipped.append(url.lastPathComponent)
                }
                activeOperation = .importingPlaylists(completed: index + 1, total: urls.count)
            }
            if imported > 0 {
                let skippedNote = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", "))."
                resultMessage = "Imported \(imported) \(imported == 1 ? "playlist" : "playlists"). Video information will resolve from Local Playlists.\(skippedNote)"
                await LocalPlaylistHydrationCoordinator.shared.startIfNeeded()
            } else if !skipped.isEmpty {
                errorMessage = "Skipped: \(skipped.joined(separator: ", "))"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
