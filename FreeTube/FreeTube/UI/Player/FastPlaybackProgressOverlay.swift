import SwiftUI

/// A compact, cancellable status while a temporary local file is prepared for >2× playback.
/// It is independent of the ordinary playback spinner: the current HLS video keeps playing.
@available(iOS 17.0, *)
struct FastPlaybackProgressOverlay: View {
    let preparation: FastPlaybackLocalFileService.ProgressUpdate
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let fraction = preparation.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .tint(.white)
            .progressViewStyle(.linear)
            .frame(width: 130)
            .accessibilityLabel("Preparing faster playback")

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel fast playback preparation")
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}
