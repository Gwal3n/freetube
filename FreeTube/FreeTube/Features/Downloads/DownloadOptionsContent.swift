import SwiftUI

/// Quality choices shared by the player download button and native video action menus.
@available(iOS 17.0, *)
struct DownloadOptionsContent: View {
    @State private var model = DownloadOptionsViewModel()

    let video: Video
    let onSelect: (VideoQuality) -> Void

    private let videoQualities: [VideoQuality] = [
        .auto, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    var body: some View {
        Section("Video") {
            ForEach(videoQualities) { quality in
                option(quality, title: quality == .auto
                       ? "Automatic (up to 1080p)"
                       : "Up to \(quality.displayName)")
            }
        }
        Section("Audio") {
            option(.audioOnly, title: "Audio only")
        }
    }

    private func option(_ quality: VideoQuality, title: String) -> some View {
        Button {
            onSelect(quality)
        } label: {
            Text(title)
            if let bytes = model.estimatedBytes[quality] {
                Text(verbatim: "≈\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
            }
        }
        .accessibilityHint(model.estimatedBytes[quality] == nil
                           ? "File size unavailable"
                           : "Approximate file size")
        .onAppear {
            guard quality == .auto else { return }
            Task { await model.loadEstimates(for: video) }
        }
    }
}
