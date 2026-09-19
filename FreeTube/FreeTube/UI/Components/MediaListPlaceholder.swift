import SwiftUI

/// Static placeholders preserve the shape of a browsing list without continuous shimmer work.
struct MediaListPlaceholder: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: MediaStyle.spacing) {
                    RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                        .fill(.quaternary)
                        .frame(
                            width: dynamicTypeSize.isAccessibilitySize ? 104 : 144,
                            height: dynamicTypeSize.isAccessibilitySize ? 58.5 : 81
                        )
                    VStack(alignment: .leading, spacing: 9) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(maxWidth: 170)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(maxWidth: 112)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 70, height: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Match `VideoRow.Accessory.actions` so loading geometry does not widen and
                    // then jump inward when the ellipsis control appears with real results.
                    Color.clear
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                }
                .mediaListRow()
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading videos")
    }
}
