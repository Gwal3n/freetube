import SwiftUI

/// Quality menu; size estimates load only when the menu first opens.
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
