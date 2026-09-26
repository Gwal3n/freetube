import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct PlaylistActionsContent: View {
    let playlist: Playlist
    let model: PlaylistActionsModel
    var offersOpen = false
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.openURL) private var openURL

    var body: some View {
        if offersOpen {
            Button {
                MediaContextNavigation.open(.freetubeOpenPlaylist, id: playlist.id, player: player)
            } label: { Label("Open playlist", systemImage: "rectangle.stack") }
        }
        if let url = playlist.youtubeURL {
            ShareLink(item: url) { Label("Share playlist", systemImage: "square.and.arrow.up") }
            Button { UIPasteboard.general.string = url.absoluteString } label: {
                Label("Copy URL", systemImage: "link")
            }
            Button { openURL(url) } label: { Label("Open in browser", systemImage: "safari") }
        }
        Divider()
        Button { Task { await model.toggleSave(playlist) } } label: {
            Label(
                model.isSaving ? "Saving…" : (model.isSaved ? "Remove saved playlist" : "Save playlist"),
                systemImage: model.isSaved ? "bookmark.fill" : "bookmark"
            )
        }
        .disabled(model.isSaving || !model.hasLoaded)
    }
}
