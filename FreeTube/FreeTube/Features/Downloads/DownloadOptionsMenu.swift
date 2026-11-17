import SwiftUI

@available(iOS 17.0, *)
struct DownloadOptionsMenu<MenuLabel: View>: View {
    let video: Video
    let onSelect: (VideoQuality) -> Void
    let onShowDetails: () -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            DownloadOptionsContent(
                video: video,
                onSelect: onSelect,
                onShowDetails: onShowDetails
            )
        } label: {
            label()
        }
        .accessibilityLabel("Download")
        .onAppear {
            DownloadOptionsViewModel.prefetch(for: video)
        }
    }
}
