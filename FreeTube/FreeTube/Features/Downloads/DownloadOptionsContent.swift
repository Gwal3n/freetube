import SwiftUI

@available(iOS 17.0, *)
struct DownloadOptionsContent: View {
    @AppStorage("defaultDownloadQuality") private var defaultDownloadQualityRaw = VideoQuality.p360.rawValue

    let video: Video
    let onSelect: (VideoQuality) -> Void
    let onShowDetails: () -> Void

    private var defaultQuality: VideoQuality {
        VideoQuality(rawValue: defaultDownloadQualityRaw) ?? .p360
    }

    var body: some View {
        Button {
            onSelect(defaultQuality)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        Button(action: onShowDetails) {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .onAppear {
            DownloadOptionsViewModel.prefetch(for: video)
        }
    }
}
