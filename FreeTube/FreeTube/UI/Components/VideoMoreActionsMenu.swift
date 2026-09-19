import SwiftUI
import SwiftData
import UIKit

/// Reusable trailing ellipsis Menu for `Video` items. Used by search results, history,
/// the playback queue, and anywhere else a video appears in a list. Owns its own favorites
/// `@Query`, share-file sheet, and add-to-playlist sheet so callers just drop it in next to
/// the row's main tap target.
///
/// Local-action rules:
///   - Open in browser, Copy URL: always shown
///   - Open in… : shown only when the video has a local downloaded file
///   - Add to favorites / Remove from favorites: always local
///   - Add to playlist: always local
///   - Remove downloaded file: shown only when the video has a local downloaded file
@available(iOS 17.0, *)
struct VideoMoreActionsMenu: View {
    let video: Video
    var offersPlayNext = false
    var onRemoveFromUpNext: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(PlayerStateManager.self) private var player
    @Query private var favorites: [FavoriteVideo]

    @State private var shareFileURL: URL?
    @State private var addToPlaylistVideo: Video?

    init(video: Video, offersPlayNext: Bool = false, onRemoveFromUpNext: (() -> Void)? = nil) {
        self.video = video
        self.offersPlayNext = offersPlayNext
        self.onRemoveFromUpNext = onRemoveFromUpNext
        let videoID = video.id
        _favorites = Query(filter: #Predicate<FavoriteVideo> { $0.videoID == videoID })
    }

    var body: some View {
        Menu {
            menuContent
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
    }

    @ViewBuilder
    private var menuContent: some View {
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
        if !video.channelID.isEmpty {
            Button {
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
        Button {
            addToPlaylistVideo = video
        } label: {
            Label("Save to local playlist", systemImage: "bookmark")
        }
        Button {
            toggleFavorite()
        } label: {
            if isFavorite {
                Label("Remove from favorites", systemImage: "hand.thumbsup.fill")
            } else {
                Label("Add to favorites", systemImage: "hand.thumbsup")
            }
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

    private var isFavorite: Bool {
        favorites.contains { $0.videoID == video.id }
    }

    /// Toggles the device-local favorite without contacting YouTube.
    private func toggleFavorite() {
        let wasFavorite = isFavorite
        if wasFavorite {
            for existing in favorites where existing.videoID == video.id {
                modelContext.delete(existing)
            }
        } else {
            modelContext.insert(FavoriteVideo(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL
            ))
        }
        try? modelContext.save()

    }
}
