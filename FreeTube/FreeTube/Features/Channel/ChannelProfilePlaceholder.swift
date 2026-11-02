import SwiftUI

/// Reserves the final header and first rows while channel data loads.
@available(iOS 17.0, *)
struct ChannelProfilePlaceholder: View {
    let headerOffset: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var compactThumbnailSize: CGSize {
        MediaStyle.compactVideoThumbnailSize(for: dynamicTypeSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChannelProfileBanner(
                channel: nil,
                headerOffset: headerOffset,
                height: ChannelProfileMetrics.bannerHeight
            )

            HStack(alignment: .center, spacing: ChannelProfileMetrics.headerRowSpacing) {
                Circle()
                    .fill(MediaStyle.placeholderFill)
                    .frame(
                        width: ChannelProfileMetrics.avatarSize,
                        height: ChannelProfileMetrics.avatarSize
                    )

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MediaStyle.placeholderFill)
                        .frame(maxWidth: 160)
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MediaStyle.placeholderFill)
                        .frame(maxWidth: 110)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MediaStyle.placeholderFill)
                        .frame(maxWidth: 135)
                        .frame(height: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Capsule()
                    .fill(MediaStyle.placeholderFill)
                    .frame(width: 92, height: 34)
            }
            .padding(.horizontal, ChannelProfileMetrics.headerRowInset)
            .padding(.top, 16)
            .padding(.bottom, 18)

            HStack(spacing: 26) {
                ForEach([CGFloat(54), 48, 62, 47], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MediaStyle.placeholderFill)
                        .frame(width: width, height: 12)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 17)
            .padding(.bottom, 20)

            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(MediaStyle.placeholderFill)
                    .frame(width: 82, height: 13)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            LazyVStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: MediaStyle.spacing) {
                        RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius)
                            .fill(MediaStyle.placeholderFill)
                            .frame(
                                width: compactThumbnailSize.width,
                                height: compactThumbnailSize.height
                            )
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(MediaStyle.placeholderFill)
                                .frame(maxWidth: 170)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(MediaStyle.placeholderFill)
                                .frame(maxWidth: 115)
                                .frame(height: 11)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(MediaStyle.placeholderFill)
                                .frame(width: 72, height: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(SkeletonPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading channel")
        .allowsHitTesting(false)
    }
}
