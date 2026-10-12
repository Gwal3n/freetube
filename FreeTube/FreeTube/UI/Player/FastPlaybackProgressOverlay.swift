import SwiftUI

/// A compact, cancellable status while a temporary local file is prepared for >2× playback.
/// It is independent of the ordinary playback spinner: the current HLS video keeps playing.
@available(iOS 17.0, *)
struct FastPlaybackProgressOverlay: View {
    let preparation: FastPlaybackLocalFileService.ProgressUpdate
    let rate: Double
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Preparing \(PlaybackSpeedPresets.label(rate))")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel fast playback preparation")
            }

            Group {
                if let fraction = preparation.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .tint(.white)
            .progressViewStyle(.linear)
            .accessibilityLabel("Preparing faster playback")
        }
        .frame(width: 188, alignment: .leading)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 3)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}
