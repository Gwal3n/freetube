import SwiftUI

/// Native download menu. Size metadata starts loading only when its first item is shown, so
/// merely displaying the player does not issue another video-info request. Menus can show a
/// secondary Text in each button label; available estimates appear there on the next opening if
/// the request has not finished while the menu is already visible.
@available(iOS 17.0, *)
struct DownloadOptionsMenu: View {
    let video: Video
    let onSelect: (VideoQuality) -> Void

    var body: some View {
        Menu {
            DownloadOptionsContent(video: video, onSelect: onSelect)
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.title3.weight(.semibold))
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Download")
    }
}
