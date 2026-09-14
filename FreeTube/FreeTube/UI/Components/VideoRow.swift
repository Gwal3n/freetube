import SwiftUI
import Kingfisher

/// Horizontal compact video row — used in search results, history, library lists.
///
/// Set `showsMoreMenu: true` to render a trailing ellipsis Menu next to the row content
/// (open in browser, copy URL, favorites, add to playlist, downloads). The Menu lives as a
/// sibling of the main tap target so taps on it don't trigger `onTap`.
@available(iOS 17.0, *)
struct VideoRow: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let video: Video
    var showsMoreMenu: Bool
    var offersPlayNext: Bool
    var playbackProgress: Double?
    var reservesMoreMenuSpace: Bool
    var onTap: () -> Void

    /// Keep the action closure last so existing SwiftUI call sites can continue to use trailing-
    /// closure syntax as optional row capabilities are added.
    init(
        video: Video,
        showsMoreMenu: Bool = false,
        offersPlayNext: Bool = false,
        playbackProgress: Double? = nil,
        reservesMoreMenuSpace: Bool = false,
        onTap: @escaping () -> Void = {}
    ) {
        self.video = video
        self.showsMoreMenu = showsMoreMenu
        self.offersPlayNext = offersPlayNext
        self.playbackProgress = playbackProgress
        self.reservesMoreMenuSpace = reservesMoreMenuSpace
        self.onTap = onTap
    }

    /// Playback count + relative upload date joined by a middle dot. Either half can be empty
    /// (older listings sometimes omit one), so we filter before joining to avoid stray separators.
    private var statsLine: String {
        [video.viewCountString, video.publishedRelative ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                content
            }
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint("Plays video")

            if showsMoreMenu {
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext)
            } else if reservesMoreMenuSpace {
                Color.clear
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .accessibilityHidden(true)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if offersPlayNext {
                Button {
                    player.enqueueNext(video)
                } label: {
                    Label("Play next", systemImage: "text.insert")
                }
                .tint(.accentColor)
            }
        }
        .listRowSeparator(.hidden)
    }

    private var rowAccessibilityLabel: String {
        [video.title, video.channelName, statsLine, video.durationString]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var content: some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            VideoThumbnail(
                video: video,
                size: CGSize(width: dynamicTypeSize.isAccessibilitySize ? 104 : 144,
                             height: dynamicTypeSize.isAccessibilitySize ? 58.5 : 81),
                progress: playbackProgress
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(MediaStyle.title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                Text(video.channelName)
                    .font(MediaStyle.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !statsLine.isEmpty {
                    Text(statsLine)
                        .font(MediaStyle.tertiaryMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
