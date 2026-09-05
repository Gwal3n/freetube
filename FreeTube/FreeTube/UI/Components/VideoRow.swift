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
    let video: Video
    var showsMoreMenu: Bool
    var offersPlayNext: Bool
    var playbackProgress: Double?
    var onTap: () -> Void

    /// Keep the action closure last so existing SwiftUI call sites can continue to use trailing-
    /// closure syntax as optional row capabilities are added.
    init(
        video: Video,
        showsMoreMenu: Bool = false,
        offersPlayNext: Bool = false,
        playbackProgress: Double? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.video = video
        self.showsMoreMenu = showsMoreMenu
        self.offersPlayNext = offersPlayNext
        self.playbackProgress = playbackProgress
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
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if showsMoreMenu {
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext)
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
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                KFImage(video.thumbnailURL)
                    .thumbnail(size: CGSize(width: 168, height: 96)) {
                        Color.gray.opacity(0.2)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 168, height: 96)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if !video.durationString.isEmpty {
                    Text(video.durationString)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(video.isLive ? Color.red : Color.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }

                if let playbackProgress {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Color.black.opacity(0.32)
                                Color.red
                                    .frame(width: proxy.size.width * min(max(playbackProgress, 0), 1))
                            }
                            .frame(height: 3)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: 168, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(video.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !statsLine.isEmpty {
                    Text(statsLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}
