import SwiftUI

/// Quality menu; size estimates load only when the menu first opens.
@available(iOS 17.0, *)
struct DownloadOptionsMenu<MenuLabel: View>: View {
    let video: Video
    let onSelect: (VideoQuality) -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            DownloadOptionsContent(video: video, onSelect: onSelect)
        } label: {
            label()
        }
        .accessibilityLabel("Download")
    }
}
