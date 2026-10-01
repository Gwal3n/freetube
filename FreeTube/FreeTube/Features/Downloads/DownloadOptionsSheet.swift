import SwiftUI

/// A per-download choice. It does not change the player's preferred playback quality.
@available(iOS 17.0, *)
struct DownloadOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (VideoQuality) -> Void

    private let videoQualities: [VideoQuality] = [
        .auto, .p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(videoQualities) { quality in
                        Button {
                            dismiss()
                            onSelect(quality)
                        } label: {
                            Label(videoLabel(for: quality), systemImage: "video")
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("Video")
                } footer: {
                    Text("The chosen quality is a maximum. The downloaded video may be lower if that quality is unavailable.")
                }

                Section("Audio") {
                    Button {
                        dismiss()
                        onSelect(.audioOnly)
                    } label: {
                        Label("Audio only", systemImage: "waveform")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func videoLabel(for quality: VideoQuality) -> String {
        if quality == .auto { return "Automatic (up to 1080p)" }
        return "Up to \(quality.displayName)"
    }
}
