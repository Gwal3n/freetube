import SwiftUI
import Kingfisher

/// Playlist list row. Used by search results, channel/library playlist lists.
///
/// Set `showsMoreMenu: true` to render a trailing ellipsis Menu next to the row content
/// (open in browser, copy URL, favorites). The Menu is a sibling of the tap target so taps
/// on it don't trigger `onTap` / the surrounding NavigationLink.
@available(iOS 17.0, *)
struct PlaylistRow: View {
    let playlist: Playlist
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Optional tap handler. **Leave nil when wrapping this row inside a `NavigationLink`** —
    /// an inner `Button` swallows the link's tap and pushing never happens. We only attach a
    /// `Button` when the caller actually provides a handler.
    var onTap: (() -> Void)? = nil

    var showsMoreMenu: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(ResponsiveButtonStyle())
            } else {
                content
            }

            if showsMoreMenu {
                PlaylistMoreActionsMenu(playlist: playlist)
            }
        }
        .mediaListRow()
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                KFImage(playlist.thumbnailURL)
                    .thumbnail(size: CGSize(width: 96, height: 56)) {
                        MediaStyle.placeholderFill
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 56)

                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 10, weight: .semibold))
                    if let count = playlist.videoCount {
                        Text(verbatim: count.formatted(.number.notation(.compactName)))
                            .accessibilityLabel("\(count) videos")
                    } else {
                        Text("Playlist")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.76))
            }
            .frame(width: 96, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(MediaStyle.title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                if let channelName = playlist.channelName, !channelName.isEmpty {
                    Text(channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // No manual chevron — when this row sits inside a `NavigationLink` in a List, iOS adds
            // its own disclosure chevron. Drawing one here was rendering a duplicate accessory.
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
