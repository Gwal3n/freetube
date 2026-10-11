import SwiftUI

/// A compact, cancellable status while a temporary local file is prepared for >2× playback.
/// It is independent of the ordinary playback spinner: the current HLS video keeps playing.
@available(iOS 17.0, *)
struct FastPlaybackProgressOverlay: View {
    let requestedRate: Double
    let phase: FastPlaybackLocalFileService.Phase
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let progress {
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(width: 36)
            } else {
                ProgressView()
                    .tint(.white)
                    .controlSize(.mini)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing \(PlaybackSpeedPresets.label(requestedRate)) playback")
                    .font(.caption.weight(.semibold))
                Text(phaseText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

    private var phaseText: String {
        if let progress {
            return "\(phase.rawValue) \(Int((progress * 100).rounded()))%"
        }
        return phase.rawValue
    }
}
