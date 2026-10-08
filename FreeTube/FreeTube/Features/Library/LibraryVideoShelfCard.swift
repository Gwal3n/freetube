import SwiftUI

/// Compact history artwork in the Library shelf. It uses the same thumbnail launch anchor as
/// feed rows, so opening from the shelf starts at the tapped image instead of the floating player.
@available(iOS 17.0, *)
struct LibraryVideoShelfCard: View {
    @Environment(PlayerStateManager.self) private var player
    @AppStorage("showHistoryProgressBars") private var showHistoryProgressBars = true
    @State private var launchAnchor = VideoLaunchAnchor()

    let entry: WatchHistorySnapshot
    let canMarkComplete: Bool

    private var video: Video {
        Video(
            id: entry.videoID,
            title: entry.title,
            channelID: entry.channelID ?? "",
            channelName: entry.channelName,
            channelThumbnailURL: nil,
            thumbnailURL: entry.thumbnailURL,
            duration: entry.duration > 0 ? entry.duration : nil,
            viewCount: nil,
            publishedAt: nil,
            descriptionSnippet: nil,
            isLive: false,
            isShort: false
        )
    }

    var body: some View {
        Button(action: openVideo) {
            VStack(alignment: .leading, spacing: 6) {
                VideoThumbnail(
                    video: video,
                    size: CGSize(width: 160, height: 90),
                    progress: showHistoryProgressBars ? entry.resumableProgress : nil
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    launchAnchor.frame = frame
                }
                Text(entry.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 160, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle())
        .accessibilityLabel("Play \(entry.title)")
        .videoContextMenu(
            video: video,
            offersPlayNext: true,
            onPlay: openVideo,
            onMarkComplete: canMarkComplete && entry.duration > 0 && player.currentVideo?.id != entry.videoID
                ? markComplete : nil,
            onRemoveFromHistory: removeFromHistory
        )
    }

    private func openVideo() {
        player.prepareLaunch(for: entry.videoID, from: launchAnchor.frame)
        player.load(video)
    }

    private func markComplete() {
        Task {
            await PersistenceWriter.shared.updateWatchProgress(
                videoID: entry.videoID,
                position: entry.duration,
                duration: entry.duration,
                notifyObservers: true
            )
        }
    }

    private func removeFromHistory() {
        Task { await PersistenceWriter.shared.deleteWatchHistory(videoID: entry.videoID) }
    }
}
