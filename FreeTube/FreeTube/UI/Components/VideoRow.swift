import SwiftUI
import Kingfisher

/// Horizontal compact video row — used in search results, history, library lists.
///
/// Its accessory mode deliberately describes the few supported row contexts instead of exposing
/// independent flags that can form visually invalid combinations.
@available(iOS 17.0, *)
struct VideoRow: View {
    enum Accessory {
        case none
        case actions(offersPlayNext: Bool)
        case reserved
    }

    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let video: Video
    var accessory: Accessory
    var playbackProgress: Double?
    var onTap: () -> Void

    /// Keep the action closure last so existing SwiftUI call sites can continue to use trailing-
    /// closure syntax as optional row capabilities are added.
    init(
        video: Video,
        accessory: Accessory = .none,
        playbackProgress: Double? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.video = video
        self.accessory = accessory
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
            .buttonStyle(ResponsiveButtonStyle())
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint("Plays video")

            switch accessory {
            case .none:
                EmptyView()
            case .actions(let offersPlayNext):
                VideoMoreActionsMenu(video: video, offersPlayNext: offersPlayNext)
            case .reserved:
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
        .listRowInsets(MediaStyle.listRowInsets)
    }

    private var offersPlayNext: Bool {
        guard case .actions(let offersPlayNext) = accessory else { return false }
        return offersPlayNext
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
