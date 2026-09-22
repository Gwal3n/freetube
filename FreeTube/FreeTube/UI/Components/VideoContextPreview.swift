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
        VStack(alignment: .leading, spacing: 0) {
            VideoThumbnail(
                video: video,
                size: CGSize(width: previewWidth, height: previewWidth * 9 / 16),
                cornerRadius: 0
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [video.title, metadata, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
