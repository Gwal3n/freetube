import SwiftUI
import Kingfisher

/// Vertical "feed" video card — used in Home, Subscriptions, Channel videos.
///
/// Set `showsMoreMenu: true` to render the trailing ellipsis Menu (open in browser, copy URL,
/// favorites, add to playlist, downloads) on the metadata row. The Menu sits as a sibling of
/// the card's main tap target so its taps don't trigger `onTap`.
@available(iOS 17.0, *)
struct VideoCard: View {
    let video: Video
    var onTap: () -> Void = {}
    var showsMoreMenu: Bool = false

    /// Channel name plus the playback count and relative upload date. Joined by middle dots so
    /// the line reads naturally and any missing segment is dropped without leaving stray
    /// separators ("Channel" / "Channel • 1.2M views" / "Channel • 1.2M views • 3 days ago").
    private var metadataLine: String {
        let parts = [video.channelName, video.viewCountString, video.publishedRelative ?? ""]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(video.title), \(video.channelName)"))

            // Metadata row is split into its own HStack so the ellipsis Menu can live as a
            // sibling of the title/avatar tap target (which still routes to `onTap`). Nesting
            // the Menu inside the outer Button would route taps to playback instead of to the
            // Menu, since SwiftUI's outer Button consumes the gesture first.
            metadataRow
        }
    }

    private var thumbnail: some View {
        GeometryReader { proxy in
            VideoThumbnail(
                video: video,
                size: CGSize(width: proxy.size.width, height: proxy.size.width * 9 / 16)
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
                            Circle().fill(.gray.opacity(0.2))
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(MediaStyle.title)
                            .lineLimit(2)
                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsMoreMenu {
                VideoMoreActionsMenu(video: video)
            }
        }
        .padding(.horizontal)
    }
}
