import SwiftUI

/// Native context-menu preview shared by compact rows and full-width video cards.
///
/// The surrounding blur, lifted-card animation, haptic, menu placement, and interactive
/// dismissal all come from SwiftUI's `contextMenu(menuItems:preview:)`; this view supplies only
/// the media content that iOS presents inside that system interaction.
@available(iOS 17.0, *)
struct VideoContextPreview: View {
    let video: Video

    private let previewWidth: CGFloat = 320

    private var metadata: String {
        [video.channelName, video.viewCountString, video.publishedRelative ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    var body: some View {
        DeArrowVideoContent(video: video) { branding in
            VStack(alignment: .leading, spacing: 0) {
                VideoThumbnail(
                    video: video,
                    size: CGSize(width: previewWidth, height: previewWidth * 9 / 16),
                    cornerRadius: 0,
                    replacementData: branding.thumbnailData(for: video),
                    replacementCacheKey: branding.thumbnailCacheKey(for: video)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(branding.title(for: video))
                        .contentTransition(.opacity)
                        .font(.headline)
                        .lineLimit(2)

                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(width: previewWidth)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(title: branding.title(for: video)))
        }
    }

    private func accessibilityLabel(title: String) -> String {
        [title, metadata, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
