import SwiftUI

@available(iOS 17.0, *)
struct EditLocalPlaylistSheet: View {
    let playlist: LocalPlaylistSnapshot
    let onSave: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var descriptionText: String
    @State private var isSaving = false

    init(playlist: LocalPlaylistSnapshot, onSave: @escaping (String, String?) async -> Void) {
        self.playlist = playlist
        self.onSave = onSave
        _title = State(initialValue: playlist.title)
        _descriptionText = State(initialValue: playlist.descriptionText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Playlist name", text: $title)
                }
                Section("Description") {
                    TextField("Optional description", text: $descriptionText, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(cleanTitle.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    private var cleanTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !cleanTitle.isEmpty, !isSaving else { return }
        isSaving = true
        let cleanDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        await onSave(cleanTitle, cleanDescription.isEmpty ? nil : cleanDescription)
        isSaving = false
        dismiss()
    }
}
