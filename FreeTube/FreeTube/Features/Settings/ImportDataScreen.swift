import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct ImportDataScreen: View {
    @State private var showingSubscriptionImporter = false
    @State private var showingPlaylistImporter = false
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    private let playlistService = LocalPlaylistService()

    var body: some View {
        Form {
            Section {
                Button {
                    showingSubscriptionImporter = true
                } label: {
                    Label("Import Subscriptions CSV", systemImage: "person.2.badge.plus")
                }
                .disabled(isImporting)
                Button {
                    showingPlaylistImporter = true
                } label: {
                    Label("Import Playlist CSV Files", systemImage: "music.note.list")
                }
                .disabled(isImporting)
            } footer: {
                Text("Imports stay on this device. Each playlist CSV becomes a separate personal playlist.")
            }

            if isImporting {
                Section("Importing") {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Adding playlists to your library…")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Import Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingSubscriptionImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importSubscriptions(result)
        }
        .fileImporter(
            isPresented: $showingPlaylistImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            Task { await importPlaylists(result) }
        }
        .alert("Import Complete", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(resultMessage ?? "") }
        .alert("Couldn’t Import Data", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func importSubscriptions(_ result: Result<[URL], Error>) {
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
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            var imported = 0
            var skipped = [String]()
            for url in try result.get() {
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
