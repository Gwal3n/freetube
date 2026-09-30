import SwiftUI

@available(iOS 17.0, *)
struct AddVideoToPlaylistSheet: View {
    let playlistID: String
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddVideoToPlaylistViewModel()
    @FocusState private var linkFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube link or video ID", text: Bindable(model).link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .focused($linkFocused)
                        .onSubmit { Task { await add() } }
                } footer: {
                    Text("Paste a video link or ID. The video information is saved locally with this playlist.")
                }
            }
            .navigationTitle("Add Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await add() }
                    } label: {
                        if model.isAdding {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAdding)
                }
            }
            .errorToast(Bindable(model).errorState)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isAdding)
        .task { linkFocused = true }
    }

    private func add() async {
        if await model.add(to: playlistID) { dismiss() }
    }
}
