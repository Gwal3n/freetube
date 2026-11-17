import SwiftUI

/// Compact download menu: one-tap Auto (the saved default) plus an entry that opens the details sheet.
@available(iOS 17.0, *)
struct DownloadOptionsContent: View {
    @AppStorage("defaultDownloadQuality") private var defaultDownloadQualityRaw = VideoQuality.p360.rawValue

    let onSelect: (VideoQuality) -> Void
    let onShowDetails: () -> Void

    private var defaultQuality: VideoQuality {
        VideoQuality(rawValue: defaultDownloadQualityRaw) ?? .p360
    }

    var body: some View {
        Button {
            onSelect(defaultQuality)
        } label: {
            Label("Auto", systemImage: "arrow.down.circle")
            Text(verbatim: defaultQuality.displayName)
        }
        Button(action: onShowDetails) {
            Label("Download details…", systemImage: "slider.horizontal.3")
        }
    }
}
