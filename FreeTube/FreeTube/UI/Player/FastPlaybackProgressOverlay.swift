import SwiftUI

/// A compact, cancellable status while a temporary local file is prepared for >2× playback.
/// It is independent of the ordinary playback spinner: the current HLS video keeps playing.
@available(iOS 17.0, *)
struct FastPlaybackProgressOverlay: View {
    let preparation: FastPlaybackLocalFileService.ProgressUpdate
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Preparing faster playback")
                    .font(.caption.weight(.semibold))

                if let fraction = preparation.fraction {
                    ProgressView(value: fraction)
                        .tint(.white)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .tint(.white)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 4) {
                    Text(preparation.phase.rawValue)
                    Spacer(minLength: 4)
                    if let totalBytes = preparation.totalBytes {
                        Text("\(formatted(preparation.completedBytes)) / \(formatted(totalBytes))")
                            .monospacedDigit()
                    } else if preparation.completedBytes > 0 {
                        Text("\(formatted(preparation.completedBytes)) downloaded")
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(width: 215)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel fast playback preparation")
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
