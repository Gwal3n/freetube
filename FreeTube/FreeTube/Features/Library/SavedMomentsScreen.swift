import SwiftUI

/// Timestamp bookmarks live within History rather than adding another Library destination.
@available(iOS 17.0, *)
struct SavedMomentsScreen: View {
    let onOpen: (SavedMoment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = SavedMomentStore.shared
    @State private var searchText = ""
    @State private var momentToRename: SavedMoment?
    @State private var editedLabel = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.moments.isEmpty {
                    ContentUnavailableView(
                        "No saved moments",
                        systemImage: "bookmark",
                        description: Text("Save a moment from the player or transcript.")
                    )
                } else if filteredMoments.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredMoments) { moment in
                            Button {
                                onOpen(moment)
                            } label: {
                                HStack(spacing: 12) {
                                    VideoThumbnail(
                                        video: moment.video,
                                        size: CGSize(width: 96, height: 54),
                                        compactBadge: true
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: moment.label ?? moment.video.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(verbatim: moment.label == nil ? moment.video.channelName : moment.video.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Text(verbatim: moment.timestampText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 54)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "\(moment.label ?? moment.video.title), \(moment.timestampText)"))
                            .accessibilityHint("Play from this saved moment")
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.remove(id: moment.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editedLabel = moment.label ?? ""
                                    momentToRename = moment
                                } label: {
                                    Label("Edit label", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.remove(id: moment.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search saved moments")
        }
        .alert("Name moment", isPresented: Binding(
            get: { momentToRename != nil },
            set: { if !$0 { momentToRename = nil } }
        )) {
            TextField("Label", text: $editedLabel)
            Button("Save") {
                if let momentToRename {
                    store.rename(id: momentToRename.id, label: editedLabel)
                }
                momentToRename = nil
            }
            Button("Cancel", role: .cancel) { momentToRename = nil }
        } message: {
            Text("Leave blank to use the video title.")
        }
    }

    // MARK: - Filtering

    private var filteredMoments: [SavedMoment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.moments }
        return store.moments.filter {
            ($0.label ?? "").localizedStandardContains(query)
                || $0.video.title.localizedStandardContains(query)
                || $0.video.channelName.localizedStandardContains(query)
        }
    }
}
