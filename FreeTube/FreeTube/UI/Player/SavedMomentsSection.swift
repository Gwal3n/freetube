import SwiftUI

/// A video's saved timestamps belong beside its other player details, not only in global History.
/// The store is observed here so saving a moment does not invalidate the entire player panel.
@available(iOS 17.0, *)
struct SavedMomentsSection: View {
    let videoID: String
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = SavedMomentStore.shared
    @State private var isExpanded = false

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
                        .padding(.horizontal, 20)
                        .accessibilityLabel(Text(verbatim: "\(label), \(moment.timestampText)"))
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}
