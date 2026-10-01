import SwiftUI

/// Native download menu. Size metadata starts loading only when its first item is shown, so
/// merely displaying the player does not issue another video-info request. Menus can show a
/// secondary Text in each button label; available estimates appear there on the next opening if
/// the request has not finished while the menu is already visible.
@available(iOS 17.0, *)
struct DownloadOptionsMenu: View {
    @State private var model = DownloadOptionsViewModel()

    let video: Video
    let onSelect: (VideoQuality) -> Void

    private let videoQualities: [VideoQuality] = [
        .auto, .p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    var body: some View {
        Menu {
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
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.title3.weight(.semibold))
                .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Download")
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
