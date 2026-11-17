import SwiftUI

/// Quality menu; the details sheet owns size estimates and the full chooser.
@available(iOS 17.0, *)
struct DownloadOptionsMenu<MenuLabel: View>: View {
    let video: Video
    let onSelect: (VideoQuality) -> Void
    @ViewBuilder let label: () -> MenuLabel
    @State private var showingDetails = false

    var body: some View {
        Menu {
            DownloadOptionsContent(
                onSelect: onSelect,
                onShowDetails: { showingDetails = true }
            )
        } label: {
            label()
        }
        .accessibilityLabel("Download")
        .sheet(isPresented: $showingDetails) {
            DownloadDetailsSheet(video: video, onDownload: onSelect)
        }
    }
}
