import SwiftUI
import SwiftData
import UIKit

/// Reusable trailing ellipsis Menu for `Video` items. Used by search results, history,
/// the playback queue, and anywhere else a video appears in a list. The action definitions are
/// shared with the native long-press context menu so both entry points remain consistent.
///
/// Local-action rules:
///   - Open in browser, Copy URL: always shown
///   - Open in… : shown only when the video has a local downloaded file
///   - Add to playlist: always local
///   - Remove downloaded file: shown only when the video has a local downloaded file
@available(iOS 17.0, *)
struct VideoMoreActionsMenu: View {
    let video: Video
    var offersPlayNext = false
    var onRemoveFromUpNext: (() -> Void)? = nil
    var onOpenChannel: (() -> Void)? = nil

    @State private var shareFileURL: URL?
    @State private var addToPlaylistVideo: Video?
    @State private var downloadModel: PlayerActionsModel?

    init(video: Video, offersPlayNext: Bool = false, onRemoveFromUpNext: (() -> Void)? = nil, onOpenChannel: (() -> Void)? = nil) {
        self.video = video
        self.offersPlayNext = offersPlayNext
        self.onRemoveFromUpNext = onRemoveFromUpNext
        self.onOpenChannel = onOpenChannel
    }

    var body: some View {
        Menu {
            VideoActionsContent(
                video: video,
                offersPlay: false,
                onPlay: nil,
                offersPlayNext: offersPlayNext,
                onRemoveFromUpNext: onRemoveFromUpNext,
                onOpenChannel: onOpenChannel,
                onDownload: startDownload,
                shareFileURL: $shareFileURL,
                addToPlaylistVideo: $addToPlaylistVideo
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More video actions")
        // Same UIActivityViewController bridge the full-screen player uses for "Open in…".
        // ShareLink would serialize `file://` URLs as plain text inside a Menu and lose the
        // mp4 UTType, so the system share sheet wouldn't show the apps that can handle it.
        .sheet(isPresented: Binding(
            get: { shareFileURL != nil },
            set: { if !$0 { shareFileURL = nil } }
        )) {
            if let url = shareFileURL {
                ActivityShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $addToPlaylistVideo) { video in
            AddToPlaylistSheet(video: video)
        }
        .errorToast(Binding(
            get: { downloadModel?.downloadError },
            set: { downloadModel?.downloadError = $0 }
        ))
    }

    private func startDownload(_ quality: VideoQuality) {
        let model = downloadModel ?? PlayerActionsModel()
        downloadModel = model
        model.startDownload(video, quality: quality)
    }

}

/// One action definition shared by the ellipsis menu and native long-press context menus.
@available(iOS 17.0, *)
private struct VideoActionsContent: View {
    let video: Video
    let offersPlay: Bool
    let onPlay: (() -> Void)?
    let offersPlayNext: Bool
    let onRemoveFromUpNext: (() -> Void)?
    let onOpenChannel: (() -> Void)?
    let onDownload: (VideoQuality) -> Void
    @Binding var shareFileURL: URL?
    @Binding var addToPlaylistVideo: Video?

    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerStateManager.self) private var player

    init(
        video: Video,
        offersPlay: Bool,
        onPlay: (() -> Void)?,
        offersPlayNext: Bool,
        onRemoveFromUpNext: (() -> Void)?,
        onOpenChannel: (() -> Void)?,
        onDownload: @escaping (VideoQuality) -> Void,
        shareFileURL: Binding<URL?>,
        addToPlaylistVideo: Binding<Video?>
    ) {
        self.video = video
        self.offersPlay = offersPlay
        self.onPlay = onPlay
        self.offersPlayNext = offersPlayNext
        self.onRemoveFromUpNext = onRemoveFromUpNext
        self.onOpenChannel = onOpenChannel
        self.onDownload = onDownload
        _shareFileURL = shareFileURL
        _addToPlaylistVideo = addToPlaylistVideo
    }

    @ViewBuilder
    var body: some View {
        if offersPlay {
            Button {
                if let onPlay { onPlay() } else { player.load(video) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
        }
        if offersPlayNext {
            Button {
                player.enqueueNext(video)
            } label: {
                Label("Play next", systemImage: "text.insert")
            }
            .disabled(player.currentVideo == nil || player.currentVideo?.id == video.id)
            Button {
                player.enqueue(video)
            } label: {
                Label("Add to queue", systemImage: "text.badge.plus")
            }
            .disabled(
                player.currentVideo == nil
                    || player.currentVideo?.id == video.id
                    || player.manualQueue.contains(where: { $0.id == video.id })
            )
            Divider()
        }
        if !video.channelID.isEmpty || onOpenChannel != nil {
            Button {
                if let onOpenChannel {
                    onOpenChannel()
                    return
                }
                let channelID = video.channelID
                let wasExpanded = player.fullScreenPresented
                if wasExpanded { player.fullScreenPresented = false }
                Task { @MainActor in
                    // Let the native Menu finish dismissing before mutating its NavigationStack.
                    // An expanded player also needs time to reveal the selected tab first.
                    try? await Task.sleep(for: .milliseconds(wasExpanded ? 180 : 100))
                    NotificationCenter.default.post(name: .freetubeOpenChannel, object: channelID)
                }
            } label: {
                Label("Go to channel", systemImage: "person.crop.circle")
            }
        }
        Button {
            if let url = watchURL { UIApplication.shared.open(url) }
        } label: {
            Label("Open in browser", systemImage: "safari")
        }
        if let localFile = DownloadManager.shared.localFile(for: video.id) {
            Button {
                shareFileURL = localFile
            } label: {
                Label("Open in…", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            if let url = watchURL { UIPasteboard.general.string = url.absoluteString }
        } label: {
            Label("Copy URL", systemImage: "link")
        }
        Divider()
        Menu {
            DownloadOptionsContent(video: video, onSelect: onDownload)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        Button {
            addToPlaylistVideo = video
        } label: {
            Label("Save to local playlist", systemImage: "bookmark")
        }
        if DownloadManager.shared.localFile(for: video.id) != nil {
            Divider()
            Button(role: .destructive) {
                DownloadManager.shared.deleteDownloaded(videoID: video.id, context: modelContext)
            } label: {
                Label("Remove downloaded file", systemImage: "trash")
            }
        }
        if let onRemoveFromUpNext {
            Divider()
            Button(role: .destructive, action: onRemoveFromUpNext) {
                Label("Remove from Up Next", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(video.id)")
    }

}

/// Native iOS context-menu presentation. SwiftUI owns the long-press recognizer, lift preview,
/// haptic, interactive cancellation, dismissal, Dynamic Type, and accessibility behavior.
@available(iOS 17.0, *)
private struct VideoContextMenuModifier: ViewModifier {
    let video: Video
    let offersPlayNext: Bool
    let onPlay: (() -> Void)?
    let onRemoveFromUpNext: (() -> Void)?
    let onOpenChannel: (() -> Void)?
    let onMarkComplete: (() -> Void)?
    let onRemoveFromHistory: (() -> Void)?

    @State private var shareFileURL: URL?
    @State private var addToPlaylistVideo: Video?
    @State private var downloadModel: PlayerActionsModel?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                VideoActionsContent(
                    video: video,
                    offersPlay: true,
                    onPlay: onPlay,
                    offersPlayNext: offersPlayNext,
                    onRemoveFromUpNext: onRemoveFromUpNext,
                    onOpenChannel: onOpenChannel,
                    onDownload: startDownload,
                    shareFileURL: $shareFileURL,
                    addToPlaylistVideo: $addToPlaylistVideo
                )
                if onMarkComplete != nil || onRemoveFromHistory != nil {
                    Divider()
                    if let onMarkComplete {
                        Button(action: onMarkComplete) {
                            Label("Mark as complete", systemImage: "checkmark.circle")
                        }
                    }
                    if let onRemoveFromHistory {
                        Button(role: .destructive, action: onRemoveFromHistory) {
                            Label("Remove from history", systemImage: "trash")
                        }
                    }
                }
            } preview: {
                VideoContextPreview(video: video)
            }
            .sheet(isPresented: Binding(
                get: { shareFileURL != nil },
                set: { if !$0 { shareFileURL = nil } }
            )) {
                if let url = shareFileURL {
                    ActivityShareSheet(activityItems: [url])
                }
            }
            .sheet(item: $addToPlaylistVideo) { video in
                AddToPlaylistSheet(video: video)
            }
            .errorToast(Binding(
                get: { downloadModel?.downloadError },
                set: { downloadModel?.downloadError = $0 }
            ))
    }

    private func startDownload(_ quality: VideoQuality) {
        let model = downloadModel ?? PlayerActionsModel()
        downloadModel = model
        model.startDownload(video, quality: quality)
    }
}

@available(iOS 17.0, *)
extension View {
    func videoContextMenu(
        video: Video,
        offersPlayNext: Bool = false,
        onPlay: (() -> Void)? = nil,
        onRemoveFromUpNext: (() -> Void)? = nil,
        onOpenChannel: (() -> Void)? = nil,
        onMarkComplete: (() -> Void)? = nil,
        onRemoveFromHistory: (() -> Void)? = nil
    ) -> some View {
        modifier(VideoContextMenuModifier(
            video: video,
            offersPlayNext: offersPlayNext,
            onPlay: onPlay,
            onRemoveFromUpNext: onRemoveFromUpNext,
            onOpenChannel: onOpenChannel,
            onMarkComplete: onMarkComplete,
            onRemoveFromHistory: onRemoveFromHistory
        ))
    }
}
