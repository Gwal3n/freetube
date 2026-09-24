import SwiftUI
import Kingfisher

/// Vertical "feed" video card — used in Home, Subscriptions, Channel videos.
///
/// Set `showsMoreMenu: true` to render the trailing ellipsis Menu (open in browser, copy URL,
/// favorites, add to playlist, downloads) on the metadata row. The Menu sits as a sibling of
/// the card's main tap target so its taps don't trigger `onTap`.
@available(iOS 17.0, *)
struct VideoCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let video: Video
    var onTap: () -> Void = {}
    var showsMoreMenu: Bool = false
    var offersPlayNext = false
    var playbackProgress: Double? = nil
    var relativeDateReference: Date? = nil

    /// Channel name plus the playback count and relative upload date. Joined by middle dots so
    /// the line reads naturally and any missing segment is dropped without leaving stray
    /// separators ("Channel" / "Channel • 1.2M views" / "Channel • 1.2M views • 3 days ago").
    private var metadataLine: String {
        let publishedText = relativeDateReference.flatMap { video.publishedText(relativeTo: $0) }
            ?? video.publishedRelative ?? ""
        let parts = [video.channelName, video.viewCountString, publishedText]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                thumbnail
            }
            .buttonStyle(ResponsiveButtonStyle())
            // The metadata control below performs the same action and carries the complete
            // spoken label. Exposing both would make VoiceOver announce every card twice.
            .accessibilityHidden(true)

            // Metadata row is split into its own HStack so the ellipsis Menu can live as a
            // sibling of the title/avatar tap target (which still routes to `onTap`). Nesting
            // the Menu inside the outer Button would route taps to playback instead of to the
            // Menu, since SwiftUI's outer Button consumes the gesture first.
            metadataRow
        }
        .videoContextMenu(video: video, offersPlayNext: true)
    }

    private var thumbnail: some View {
        GeometryReader { proxy in
            VideoThumbnail(
                video: video,
                size: CGSize(width: proxy.size.width, height: proxy.size.width * 9 / 16),
                progress: playbackProgress
            )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var metadataRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    KFImage(video.channelThumbnailURL)
                        .thumbnail(size: CGSize(width: 36, height: 36)) {
                            Circle().fill(MediaStyle.placeholderFill)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(MediaStyle.title)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        Text(metadataLine)
                            .font(MediaStyle.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(cardAccessibilityLabel)
            .accessibilityHint("Plays video")

            if showsMoreMenu {
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext)
            }
        }
        .padding(.horizontal, MediaStyle.cardHorizontalPadding)
    }

    private var cardAccessibilityLabel: String {
        [video.title, metadataLine, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
