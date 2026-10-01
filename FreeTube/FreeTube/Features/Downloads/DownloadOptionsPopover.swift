import SwiftUI

/// Native compact popover anchored to the player's download control.
@available(iOS 17.0, *)
struct DownloadOptionsPopover: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var model = DownloadOptionsViewModel()

    let video: Video
    let onSelect: (VideoQuality) -> Void

    private let videoQualities: [VideoQuality] = [
        .auto, .p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Download")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    sectionHeader("VIDEO")
                    ForEach(videoQualities) { quality in
                        option(quality, title: quality == .auto
                               ? "Automatic (up to 1080p)"
                               : "Up to \(quality.displayName)")
                    }

                    sectionHeader("AUDIO")
                    option(.audioOnly, title: "Audio only")
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .frame(width: 282, height: verticalSizeClass == .compact ? 260 : 450)
        .background(.regularMaterial)
        .presentationCompactAdaptation(.popover)
        .task(id: video.id) {
            await model.loadEstimates(for: video)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func option(_ quality: VideoQuality, title: String) -> some View {
        Button {
            onSelect(quality)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                Spacer(minLength: 0)
                if let bytes = model.estimatedBytes[quality] {
                    Text(verbatim: "≈\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if model.hasLoaded {
                    Text("Size unavailable")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(minHeight: 42)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(model.estimatedBytes[quality] == nil
                           ? "File size unavailable"
                           : "Approximate file size")
    }
}
