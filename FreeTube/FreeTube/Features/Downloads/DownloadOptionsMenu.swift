import SwiftUI

@available(iOS 17.0, *)
struct DownloadOptionsMenu<MenuLabel: View>: View {
    let video: Video
    let onSelect: (VideoQuality) -> Void
    @ViewBuilder let label: () -> MenuLabel
    @State private var showingDetails = false

    var body: some View {
        Menu {
            DownloadOptionsContent(
                video: video,
                onSelect: onSelect,
                onShowDetails: { showingDetails = true }
            )
        } label: {
            label()
        }
        .accessibilityLabel("Download")
        .onAppear {
            DownloadOptionsViewModel.prefetch(for: video)
        }
        .sheet(isPresented: $showingDetails) {
            DownloadDetailsSheet(video: video, onDownload: onSelect)
        }
    }
}
