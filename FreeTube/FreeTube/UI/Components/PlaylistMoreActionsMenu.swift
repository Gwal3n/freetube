import SwiftUI

/// Shares its actions and save state with the row's native context menu.
@available(iOS 17.0, *)
struct PlaylistMoreActionsMenu: View {
    let playlist: Playlist
    let model: PlaylistActionsModel

    var body: some View {
        Menu {
            PlaylistActionsContent(playlist: playlist, model: model)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.white)
        .accessibilityLabel("More playlist actions")
    }
}
