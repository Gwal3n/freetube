import SwiftUI
import SwiftData
import UIKit

/// Reusable trailing ellipsis Menu for `Playlist` items. Used by search results, the
/// library's user-playlists screen, and anywhere else a playlist appears in a list.
///
/// Auth-gating rules (per product spec):
///   - Open in browser, Copy URL: always shown
///   - Save playlist / Remove saved playlist: stored locally
///
/// Saved playlists are stored locally in `FavoritePlaylist` (SwiftData) — no YouTube sync.
@available(iOS 17.0, *)
struct PlaylistMoreActionsMenu: View {
    let playlist: Playlist

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var favorites: [FavoritePlaylist]

    var body: some View {
        Menu {
            if let url = playlistURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in browser", systemImage: "safari")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }
            Divider()
            Button {
                toggleFavorite()
            } label: {
                if isFavorite {
                    Label("Remove saved playlist", systemImage: "bookmark.fill")
                } else {
                    Label("Save playlist", systemImage: "bookmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// YouTube's playlist URLs use the bare playlist id, stripping the `VL` prefix YouTubeKit
    /// adds for browse requests.
    private var playlistURL: URL? {
        let bare = playlist.id.hasPrefix("VL") ? String(playlist.id.dropFirst(2)) : playlist.id
        return URL(string: "https://www.youtube.com/playlist?list=\(bare)")
    }

    private var isFavorite: Bool {
        favorites.contains { $0.playlistID == playlist.id }
    }

    private func toggleFavorite() {
        if isFavorite {
            for fav in favorites where fav.playlistID == playlist.id {
                modelContext.delete(fav)
            }
        } else {
            modelContext.insert(FavoritePlaylist(
                playlistID: playlist.id,
                title: playlist.title,
                channelName: playlist.channelName ?? "",
                thumbnailURL: playlist.thumbnailURL,
                videoCount: playlist.videoCount
            ))
        }
        try? modelContext.save()
    }
}
