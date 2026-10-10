import SwiftUI

/// Library destination for timestamp bookmarks, optionally scoped to one video's moments.
@available(iOS 17.0, *)
struct SavedMomentsScreen: View {
    let videoID: String?
    let onOpen: (SavedMoment) -> Void

    @State private var store = SavedMomentStore.shared
    @State private var searchText = ""
    @State private var momentToRename: SavedMoment?
    @State private var editedLabel = ""

    init(videoID: String? = nil, onOpen: @escaping (SavedMoment) -> Void) {
        self.videoID = videoID
        self.onOpen = onOpen
    }

    var body: some View {
        searchableContent
            .navigationTitle("Saved moments")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Rename moment", isPresented: Binding(
                get: { momentToRename != nil },
                set: { if !$0 { momentToRename = nil } }
            )) {
                TextField("Name", text: $editedLabel)
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

    @ViewBuilder
    private var searchableContent: some View {
        if videoID == nil {
            momentContent.searchable(text: $searchText, prompt: "Search saved moments")
        } else {
            momentContent
        }
    }

    @ViewBuilder
    private var momentContent: some View {
        if baseMoments.isEmpty {
            ContentUnavailableView(
                "No saved moments",
                systemImage: "bookmark",
                description: Text("Save a moment from the player or transcript.")
            )
        } else if filteredMoments.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            momentsList
        }
    }

    private var momentsList: some View {
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
                .accessibilityHint("Open the video at its latest position")
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
                        Label("Rename", systemImage: "pencil")
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

    // MARK: - Filtering

    private var baseMoments: [SavedMoment] {
        guard let videoID else { return store.moments }
        return store.moments(for: videoID)
    }

    private var filteredMoments: [SavedMoment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseMoments }
        return baseMoments.filter {
            ($0.label ?? "").localizedStandardContains(query)
                || $0.video.title.localizedStandardContains(query)
                || $0.video.channelName.localizedStandardContains(query)
        }
    }
}
