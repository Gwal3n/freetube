import SwiftUI
import UIKit

/// Reusable trailing ellipsis Menu for `Playlist` items. Used by search results, the
/// library's user-playlists screen, and anywhere else a playlist appears in a list.
///
/// Auth-gating rules (per product spec):
///   - Open in browser, Copy URL: always shown
///   - Save playlist / Remove saved playlist: stored locally
///
/// Saved playlists are complete device-local snapshots — no YouTube account sync.
@available(iOS 17.0, *)
struct PlaylistMoreActionsMenu: View {
    let playlist: Playlist

    @Environment(\.openURL) private var openURL
    @State private var isSaved = false
    @State private var isSaving = false
    private let localService = LocalPlaylistService()

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
                Task { await toggleLocalSave() }
            } label: {
                if isSaving {
                    Label("Saving…", systemImage: "progress.indicator")
                } else if isSaved {
                    Label("Remove saved playlist", systemImage: "bookmark.fill")
                } else {
                    Label("Save playlist", systemImage: "bookmark")
                }
            }
            .disabled(isSaving)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { isSaved = await localService.isRemoteSaved(id: playlist.id) }
        .onReceive(NotificationCenter.default.publisher(for: .localPlaylistsDidChange)) { _ in
            Task { isSaved = await localService.isRemoteSaved(id: playlist.id) }
        }
    }

    // MARK: - Helpers

    /// YouTube's playlist URLs use the bare playlist id, stripping the `VL` prefix YouTubeKit
    /// adds for browse requests.
    private var playlistURL: URL? {
        let bare = playlist.id.hasPrefix("VL") ? String(playlist.id.dropFirst(2)) : playlist.id
        return URL(string: "https://www.youtube.com/playlist?list=\(bare)")
    }

    private func toggleLocalSave() async {
        if isSaved {
            await localService.removeRemotePlaylist(id: playlist.id)
            isSaved = false
        } else {
            isSaving = true
            defer { isSaving = false }
            do {
                try await localService.saveRemotePlaylist(playlist)
                isSaved = true
            } catch { return }
        }
    }
}
