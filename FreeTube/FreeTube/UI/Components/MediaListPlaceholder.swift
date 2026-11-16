import SwiftUI

/// Loading rows retain the final browsing-list geometry; only their opacity gently pulses.
/// An optional header row stays interactive and unpulsed, so screens whose results begin with
/// their own title and filters keep that chrome in place while loading.
@available(iOS 17.0, *)
struct MediaListPlaceholder<Header: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var header: () -> Header

    init(@ViewBuilder header: @escaping () -> Header) {
        self.header = header
    }

    private var thumbnailSize: CGSize {
        MediaStyle.compactVideoThumbnailSize(for: dynamicTypeSize)
    }

    var body: some View {
        List {
            header()
            ForEach(0..<6, id: \.self) { index in
                placeholderRow
                    .modifier(SkeletonPulse())
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading videos")
                    .accessibilityHidden(index != 0)
                    .mediaListRow()
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
    }

    private var placeholderRow: some View {
        HStack(spacing: MediaStyle.spacing) {
            RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                .fill(.quaternary)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
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
    }
}

@available(iOS 17.0, *)
extension MediaListPlaceholder where Header == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}
