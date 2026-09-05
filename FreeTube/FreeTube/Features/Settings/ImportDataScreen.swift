import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct ImportDataScreen: View {
    @State private var showingSubscriptionImporter = false
    @State private var showingPlaylistImporter = false
    @State private var progressTitle: String?
    @State private var completedVideos = 0
    @State private var totalVideos = 0
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
                .disabled(progressTitle != nil)
                Button {
                    showingPlaylistImporter = true
                } label: {
                    Label("Import Playlist CSV Files", systemImage: "music.note.list")
                }
                .disabled(progressTitle != nil)
            } footer: {
                Text("Imports stay on this device. Each playlist CSV becomes a separate personal playlist.")
            }

            if let progressTitle {
                Section("Importing") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(progressTitle).font(.headline).lineLimit(1)
                        ProgressView(value: Double(completedVideos), total: Double(max(totalVideos, 1)))
                        Text("Resolving video information \(completedVideos) of \(totalVideos)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
        do {
            var imported = 0
            var unresolvedVideos = 0
            var skipped = [String]()
            for url in try result.get() {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let playlistID = try await playlistService.importCSV(
                        data: Data(contentsOf: url),
                        filename: url.lastPathComponent
                    )
                    progressTitle = url.deletingPathExtension().lastPathComponent
                    completedVideos = 0
                    totalVideos = 0
                    unresolvedVideos += await playlistService.hydrateImportedPlaylist(id: playlistID) { completed, total in
                        completedVideos = completed
                        totalVideos = total
                    }
                    imported += 1
                } catch {
                    skipped.append(url.lastPathComponent)
                }
            }
            progressTitle = nil
            if imported > 0 {
                let unresolvedNote = unresolvedVideos == 0
                    ? ""
                    : " \(unresolvedVideos) unavailable videos were kept by ID; importing those files again will retry them."
                let skippedNote = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", "))."
                resultMessage = "Imported \(imported) \(imported == 1 ? "playlist" : "playlists") with locally saved video information.\(unresolvedNote)\(skippedNote)"
            } else if !skipped.isEmpty {
                errorMessage = "Skipped: \(skipped.joined(separator: ", "))"
            }
        } catch {
            progressTitle = nil
            errorMessage = error.localizedDescription
        }
    }
}
