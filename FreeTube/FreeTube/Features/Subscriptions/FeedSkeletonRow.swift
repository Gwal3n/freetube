import SwiftUI

/// Feed-only loading geometry. Keeping these as real List rows leaves the header readable and
/// makes the loading state follow the user's compact or large-thumbnail preference.
@available(iOS 17.0, *)
struct FeedSkeletonRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let largeThumbnail: Bool

    @ViewBuilder
    var body: some View {
        if largeThumbnail {
            largeRow
                .padding(.top, 4)
                .padding(.bottom, 14)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)
        } else {
            compactRow
                .mediaListRow()
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)
        }
    }

    private var compactRow: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: MediaStyle.spacing) {
                RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                    .fill(.quaternary)
                    .frame(
                        width: dynamicTypeSize.isAccessibilitySize ? 104 : 144,
                        height: dynamicTypeSize.isAccessibilitySize ? 58.5 : 81
                    )

                VStack(alignment: .leading, spacing: 9) {
                    placeholderLine(width: 170, height: 12)
                    placeholderLine(width: 112, height: 12)
                    placeholderLine(width: 70, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
        }
    }

    private var largeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 7) {
                    placeholderLine(width: 240, height: 12)
                    placeholderLine(width: 150, height: 12)
                    placeholderLine(width: 108, height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
            }
            .padding(.horizontal, MediaStyle.cardHorizontalPadding)
        }
    }

    private func placeholderLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.quaternary)
            .frame(maxWidth: width)
            .frame(height: height)
    }
}
