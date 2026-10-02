import SwiftUI
import Kingfisher

/// One calm transfer/library row for the entire playlist, never one row per member video.
@available(iOS 17.0, *)
struct DownloadedPlaylistRow: View {
    let manifest: PlaylistDownloadManifest
    let downloadedCount: Int
    let currentVideoTitle: String?
    let currentVideoProgress: Double
    let onResume: () -> Void
    let onCancel: () -> Void

    private var isActive: Bool {
        [.queued, .preparing, .downloading].contains(manifest.status)
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                DownloadedPlaylistScreen(playlistID: manifest.id)
            } label: {
                HStack(spacing: 12) {
                    KFImage(manifest.thumbnailURL)
                        .thumbnail(size: CGSize(width: 82, height: 50)) {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                                .frame(width: 82, height: 50)
                                .background(.quaternary)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 82, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manifest.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if isActive, !manifest.videos.isEmpty {
                            ProgressView(value: overallProgress)
                                .tint(.white)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel playlist download")
            } else if downloadedCount < manifest.videos.count || !manifest.isPrepared {
                Button(action: onResume) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume playlist download")
            }
        }
        .mediaListRow()
    }

    private var overallProgress: Double {
        guard !manifest.videos.isEmpty else { return 0 }
        return min(1, (Double(downloadedCount) + min(1, max(0, currentVideoProgress)))
            / Double(manifest.videos.count))
    }

    private var statusText: String {
        let count = "\(downloadedCount) of \(manifest.videos.count) videos"
        if manifest.status == .preparing { return "Preparing playlist… · \(count)" }
        if manifest.status == .queued { return "Queued · \(count)" }
        if manifest.status == .downloading {
            return currentVideoTitle.map { "\(count) · \($0)" } ?? count
        }
        if manifest.status == .paused { return "Paused · \(count)" }
        if downloadedCount == manifest.videos.count, manifest.isPrepared { return "Downloaded · \(count)" }
        return "Incomplete · \(count)"
    }
}
