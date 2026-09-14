import SwiftUI

/// Static placeholders preserve the shape of a browsing list without continuous shimmer work.
struct MediaListPlaceholder: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: MediaStyle.spacing) {
                    RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                        .fill(.quaternary)
                        .frame(width: 144, height: 81)
                    VStack(alignment: .leading, spacing: 9) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 70, height: 9)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading videos")
    }
}
