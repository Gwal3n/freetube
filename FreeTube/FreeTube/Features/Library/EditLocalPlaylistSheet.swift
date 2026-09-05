import SwiftUI

@available(iOS 17.0, *)
struct EditLocalPlaylistSheet: View {
    let playlist: LocalPlaylistSnapshot
    let onSave: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var descriptionText: String

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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), cleanDescription.isEmpty ? nil : cleanDescription)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
