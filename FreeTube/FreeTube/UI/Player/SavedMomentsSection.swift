import SwiftUI

/// A video's saved timestamps belong beside its player details as well as in Library.
/// The store is observed here so saving a moment does not invalidate the entire player panel.
@available(iOS 17.0, *)
struct SavedMomentsSection: View {
    let videoID: String
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = SavedMomentStore.shared
    @State private var isExpanded = false
    @State private var momentToRename: SavedMoment?
    @State private var editedLabel = ""

    private var videoMoments: [SavedMoment] {
        store.moments(for: videoID)
    }

    @ViewBuilder
    var body: some View {
        let moments = videoMoments
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(reduceMotion ? nil : InterfaceMotion.content) {
                        isExpanded.toggle()
                    }
                } label: {
                    PlayerSectionHeading(
                        title: String(localized: "Saved moments"),
                        detail: "\(moments.count)",
                        isExpanded: isExpanded
                    )
                }
                .buttonStyle(ResponsiveButtonStyle())
                .padding(.horizontal, 16)

                if isExpanded {
                    ForEach(moments) { moment in
                        let label = moment.label ?? String(localized: "Saved moment")
                        HStack(spacing: 0) {
                            Button {
                                onSeek(moment.time)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(verbatim: label)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(verbatim: moment.timestampText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(.primary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "\(label), \(moment.timestampText)"))

                            Menu {
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
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Moment actions")
                        }
                        .padding(.horizontal, 20)
                    }
                    .transition(.opacity)
                }
            }
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
    }
}
